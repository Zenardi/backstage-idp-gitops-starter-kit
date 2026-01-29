<details>
<summary class=" summary">Table of Contents</summary>

- [Setup local environment for backstage IDP development](#setup-local-environment-for-backstage-idp-development)
- [Purpose and Workflow:](#purpose-and-workflow)
  - [Setup Guide: Traefik on KIND (WSL Environment)](#setup-guide-traefik-on-kind-wsl-environment)
    - [The `kind-config.yaml` File](#the-kind-configyaml-file)
    - [Installing Traefik](#installing-traefik)
- [Installing ArgoCD](#installing-argocd)
- [Setup GitHub Runner on Local Kubernetes](#setup-github-runner-on-local-kubernetes)
  - [Deploy and Configure ARC](#deploy-and-configure-arc)
  - [Create the GitHub self hosted runners and configure to run against your repository](#create-the-github-self-hosted-runners-and-configure-to-run-against-your-repository)
- [Crossplane Setup](#crossplane-setup)
  - [Install Crossplane with Helm Chart](#install-crossplane-with-helm-chart)
  - [Setup IAM for Crossplane](#setup-iam-for-crossplane)
- [Integration with ArgoCD](#integration-with-argocd)
  - [Set health status](#set-health-status)
  - [Set resource exclusion](#set-resource-exclusion)
  - [Increase Kubernetes client QPS](#increase-kubernetes-client-qps)
- [Monitoring: Prometheus and Grafana](#monitoring-prometheus-and-grafana)
  - [Installing Prometheus Operator](#installing-prometheus-operator)
- [Install Metric Server](#install-metric-server)
  
</details>


# Setup local environment for backstage IDP development
This project provides a comprehensive setup guide for creating a local Kubernetes development environment using KIND (Kubernetes in Docker), specifically tailored for working with the Backstage Internal Developer Portal (IDP). The setup focuses on establishing a functional cluster with Traefik as the ingress controller, enabling easy access to deployed applications via localhost.


# Purpose and Workflow:
The setup enables developers to quickly spin up a local Kubernetes environment for Backstage IDP development, testing ingress routing, and application deployments without requiring a full cloud-based cluster. It's designed for WSL environments but can be adapted for native Linux by adjusting host file configurations and port access. The guide emphasizes accessibility via localhost, making it ideal for iterative development and debugging of Backstage plugins or integrations.

---


## Setup Guide: Traefik on KIND (WSL Environment)

This guide sets up a local Kubernetes cluster using KIND within WSL, configuring Traefik as the Ingress Controller to be accessible via `localhost` on port 80.

### The `kind-config.yaml` File

We need to configure the cluster to map the container's port **30080** (where Traefik will listen) to the host's port **80** (Windows).

Create a file named `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: backstage
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080  # Traefik will listen here (HTTP)
    hostPort: 80          # Accessible via Windows localhost:80
    protocol: TCP
  - containerPort: 30443  # Traefik will listen here (HTTPS)
    hostPort: 443         # Accessible via Windows localhost:443
    protocol: TCP

```

**Create the cluster:**

```bash
create cluster --config kind-config.yaml
```

### Installing Traefik

We use Helm to install Traefik. The key step here is forcing the Service to use `NodePort` and pinning it to port `30080`, ensuring it aligns with the KIND configuration above.

```bash
# Add the repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install forcing the specific NodePorts
helm install traefik traefik/traefik \
  --create-namespace --namespace traefik \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443


# To Upgrade
helm upgrade traefik traefik/traefik -f traefik/values.yaml -n traefik 
```

# Installing ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd  --versions

helm upgrade argocd argo/argo-cd --version 9.2.3 --install --create-namespace -n argocd -f argocd/values.yaml
```

# Setup GitHub Runner on Local Kubernetes
Every time we build and push an image using github actions, we want to be deployed to Kubernetes so we need to a runner INSIDE our cluster. 
- https://github.com/actions/actions-runner-controller
- https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart
- https://github.com/actions/actions-runner-controller/blob/master/docs/quickstart.md
  

With the Kubernetes up and running, first install cert-manager
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml
```

Next, Generate a Personal Access Token (PAT) for ARC to authenticate with GitHub.
- Login to your GitHub account and Navigate to "Create new Token."
- Select repo.
- Click Generate Token and then copy the token locally ( we’ll need it later).

## Deploy and Configure ARC
```bash
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller

helm upgrade --install --namespace ackgtions-runner-system --create-namespace\
  --set=authSecret.create=true\
  --set=authSecret.github_token="REPLACE_YOUR_TOKEN_HERE"\
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller
```

## Create the GitHub self hosted runners and configure to run against your repository

Create a runnerdeployment.yaml file and copy the following YAML contents into it:

```bash
cat << EOF | kubectl apply -n actions-runner-system -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: self-hosted-runners
spec:
  replicas: 1
  template:
    spec:
      repository: Zenardi/python-app
EOF
```

# Crossplane Setup

## Install Crossplane with Helm Chart
```sh
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane \
--namespace crossplane-system \
--create-namespace crossplane-stable/crossplane

kubectl get pods -n crossplane-system
```

## Setup IAM for Crossplane

To crossplane to be able to manage cloud resources, the first step is to create a secret with IAM. 
With variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY expose in your environment, run the following command:

```sh
# Expose variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in your environment
# export AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID
# export AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY

# Create the secret
kubectl create secret generic aws-secret \
  --namespace=crossplane-system \
  --from-literal=credentials="[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"
```

The next step is to create ClusterProviderConfig with those credentials
```sh
cat << EOF | kubectl apply -f -
apiVersion: aws.m.upbound.io/v1beta1
kind: ClusterProviderConfig
metadata:
  name: aws
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: aws-secret
      key: credentials
EOF
```

# Integration with ArgoCD
In order for Argo CD to track Application resources that contain Crossplane related objects, configure it to use the annotation mechanism.

To configure it, edit the argocd-cm ConfigMap in the argocd Namespace as such:

```sh
apiVersion: v1
kind: ConfigMap
data:
  application.resourceTrackingMethod: annotation
```

## Set health status

Reference: https://docs.crossplane.io/latest/guides/crossplane-with-argo-cd/

Argo CD has a built-in health assessment for Kubernetes resources. The community directly supports some checks in Argo’s repository. For example the Provider from pkg.crossplane.io already exists which means there no further configuration needed.

Argo CD also enable customising these checks per instance, and that’s the mechanism used to provide support of Provider’s CRDs.

To configure it, edit the **argocd-cm** ConfigMap in the **argocd** Namespace.

> [!TIP]
> ProviderConfig may have no status or a status.users field.

```yaml
apiVersion: v1
kind: ConfigMap
data:
  application.resourceTrackingMethod: annotation
  resource.customizations: |
    "*.upbound.io/*":
      health.lua: |
        health_status = {
          status = "Progressing",
          message = "Provisioning ..."
        }

        local function contains (table, val)
          for i, v in ipairs(table) do
            if v == val then
              return true
            end
          end
          return false
        end

        local has_no_status = {
          "ClusterProviderConfig",
          "ProviderConfig",
          "ProviderConfigUsage"
        }

        if obj.status == nil or next(obj.status) == nil and contains(has_no_status, obj.kind) then
          health_status.status = "Healthy"
          health_status.message = "Resource is up-to-date."
          return health_status
        end

        if obj.status == nil or next(obj.status) == nil or obj.status.conditions == nil then
          if (obj.kind == "ProviderConfig" or obj.kind == "ClusterProviderConfig") and obj.status.users ~= nil then
            health_status.status = "Healthy"
            health_status.message = "Resource is in use."
            return health_status
          end
          return health_status
        end

        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "LastAsyncOperation" then
            if condition.status == "False" then
              health_status.status = "Degraded"
              health_status.message = condition.message
              return health_status
            end
          end

          if condition.type == "Synced" then
            if condition.status == "False" then
              health_status.status = "Degraded"
              health_status.message = condition.message
              return health_status
            end
          end

          if condition.type == "Ready" then
            if condition.status == "True" then
              health_status.status = "Healthy"
              health_status.message = "Resource is up-to-date."
            end
          end
        end

        return health_status

    "*.crossplane.io/*":
      health.lua: |
        health_status = {
          status = "Progressing",
          message = "Provisioning ..."
        }

        local function contains (table, val)
          for i, v in ipairs(table) do
            if v == val then
              return true
            end
          end
          return false
        end

        local has_no_status = {
          "Composition",
          "CompositionRevision",
          "DeploymentRuntimeConfig",
          "ClusterProviderConfig",
          "ProviderConfig",
          "ProviderConfigUsage"
        }
        if obj.status == nil or next(obj.status) == nil and contains(has_no_status, obj.kind) then
            health_status.status = "Healthy"
            health_status.message = "Resource is up-to-date."
          return health_status
        end

        if obj.status == nil or next(obj.status) == nil or obj.status.conditions == nil then
          if (obj.kind == "ProviderConfig" or obj.kind == "ClusterProviderConfig") and obj.status.users ~= nil then
            health_status.status = "Healthy"
            health_status.message = "Resource is in use."
            return health_status
          end
          return health_status
        end

        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "LastAsyncOperation" then
            if condition.status == "False" then
              health_status.status = "Degraded"
              health_status.message = condition.message
              return health_status
            end
          end

          if condition.type == "Synced" then
            if condition.status == "False" then
              health_status.status = "Degraded"
              health_status.message = condition.message
              return health_status
            end
          end

          if contains({"Ready", "Healthy", "Offered", "Established", "ValidPipeline", "RevisionHealthy"}, condition.type) then
            if condition.status == "True" then
              health_status.status = "Healthy"
              health_status.message = "Resource is up-to-date."
            end
          end
        end

        return health_status
```

## Set resource exclusion 
Crossplane providers generate a ProviderConfigUsage for each managed resource (MR) they handle. This resource enables representing the relationship between MR and a ProviderConfig so that the controller can use it as a finalizer when you delete a ProviderConfig. End users of Crossplane don’t need to interact with this resource.

A growing number of resources and types can impact Argo CD UI reactivity. To help keep this number low, Crossplane recommend hiding all ProviderConfigUsage resources from Argo CD UI.

To configure resource exclusion edit the **argocd-cm** ConfigMap in the **argocd** Namespace as such:

```sh
apiVersion: v1
kind: ConfigMap
data:
  resource.exclusions: |
    - apiGroups:
      - "*"
      kinds:
      - ProviderConfigUsage
```

## Increase Kubernetes client QPS 
As the number of CRDs grow on a control plane it increases the amount of queries Argo CD Application Controller needs to send to the Kubernetes API. If this is the case you can increase the rate limits of the Argo CD Kubernetes client.

Set the environment variable ARGOCD_K8S_CLIENT_QPS to 300 for improved compatibility with multiple CRDs.

The default value of ARGOCD_K8S_CLIENT_QPS is 50, modifying the value also updates ARGOCD_K8S_CLIENT_BURST as it is default to ARGOCD_K8S_CLIENT_QPS x 2.


# Monitoring: Prometheus and Grafana

## Installing Prometheus Operator
Using **kube-prometheus method**, install Prometheus operator.

* Documentation: [install-using-kube-prometheus](https://prometheus-operator.dev/docs/getting-started/installation/#install-using-kube-prometheus)

The easiest way of starting with the Prometheus Operator is by deploying it as part of kube-prometheus. kube-prometheus deploys the Prometheus Operator and already schedules a Prometheus called prometheus-k8s with alerts and rules by default.

We are going to deploy a compiled version of the Kubernetes manifests.

You can either clone the kube-prometheus from GitHub:
```sh
git clone https://github.com/prometheus-operator/kube-prometheus.git
```

or download the current main branch as zip file and extract its contents:

[github.com/prometheus-operator/kube-prometheus/archive/main.zip](github.com/prometheus-operator/kube-prometheus/archive/main.zip)

Once you have the files on your machine change into the project’s root directory and run the following commands:

```sh
# Create the namespace and CRDs, and then wait for them to be available before creating the remaining resources
kubectl create -f manifests/setup

# Wait until the "servicemonitors" CRD is created. The message "No resources found" means success in this context.
until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done

kubectl create -f manifests/
```

We create the namespace and CustomResourceDefinitions first to avoid race conditions when deploying the monitoring components. Alternatively, the resources in both folders can be applied with a single command:

```sh
kubectl create -f manifests/setup -f manifests
```

But it may be necessary to run the command multiple times for all components to be created successfully.

> [!note] Note: For versions before Kubernetes v1.20.z refer to the Kubernetes compatibility matrix in order to choose a compatible branch.

> [!note] Note: If you used Kube-Prometheus as the installation method, we would recommend you to follow this page to learn how to access the resources provided.

Create the RBAC, Prometheus and Alert Manager
```sh
kubectl apply -f monitoring/prometheus-operator/prometheus-rbac.yaml
kubectl apply -f monitoring/prometheus-operator/prometheus-prometheus.yaml
kubectl apply -f monitoring/prometheus-operator/alertmanager-alertmanager.yaml
```

# Install Metric Server

Install metric server so HPA could catch metrics.

```sh
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

helm install metrics-server metrics-server/metrics-server --version 3.13.0 \
-f metrics-server/values.yaml \
-n kube-system

# OR
kubectl apply -f metrics-server/components.yaml
```