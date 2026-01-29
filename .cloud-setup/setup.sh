# !/bin/bash


################################################################################
########## Use this script to prepare a kubernetes cluster with the necessary ##
########## components to run the Backstage GitOps setup. #######################
################################################################################

####################################################
############# Cloud Setup Script ###################
####################################################


#############################################
#### Environment Setup ######################
#############################################
export SELFHOSTEDRUNNER_TOKEN=""
export GH_ORG_NAME="zenardi-org"
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""

##########################
#### Traefik Setup #######
##########################
echo "------------------------"
echo "[INFO] Setting up Traefik Ingress Controller..."
echo "------------------------"

helm install traefik traefik/traefik \
  --create-namespace --namespace traefik \
  -f ../traefik/values.yaml

echo "------------------------"
echo "[INFO] Finish Traefik Setup..."
echo "------------------------"


##########################
#### ARGOCD Setup ########
##########################
echo "------------------------"
echo "[INFO] Setting up Argo CD..."
echo "------------------------"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade argocd argo/argo-cd --version 9.2.3 --install --create-namespace -n argocd -f ../argocd/values.yaml

echo "------------------------"
echo "[INFO] Finish Argo CD Setup..."
echo "------------------------"


##############################################
#### GitHub Self-Hosted Runners Setup ########
##############################################
echo "------------------------"
echo "[INFO] Setting up GitHub Self-Hosted Runners..."
echo "------------------------"

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml

helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller

helm upgrade --install --namespace actions-runner-system --create-namespace\
  --set=authSecret.create=true\
  --set=authSecret.github_token="$SELFHOSTEDRUNNER_TOKEN"\
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller

echo "------------------------"
echo "[INFO] Creating GitHub Self-Hosted Runners resources..."
echo "------------------------"

cat << EOF | kubectl apply -n actions-runner-system -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-runner-sa
  namespace: actions-runner-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-cluster-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: github-runner-cluster-role-binding
subjects:
- kind: ServiceAccount
  name: github-runner-sa
  namespace: actions-runner-system
roleRef:
  kind: ClusterRole
  name: github-runner-cluster-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: self-hosted-runners-org
spec:
  replicas: 1
  template:
    spec:
      serviceAccountName: github-runner-sa
      organization: $GH_ORG_NAME
EOF

echo "------------------------"
echo "[INFO] Finish GitHub Self-Hosted Runners Setup..."
echo "------------------------"


##############################
### CROSSPLANE SETUP #########
##############################
echo "------------------------"
echo "[INFO] Setting up Crossplane..."
echo "------------------------"

helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane \
--namespace crossplane-system \
--create-namespace crossplane-stable/crossplane


kubectl create secret generic aws-secret \
  --namespace=crossplane-system \
  --from-literal=credentials="[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY"

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

echo "------------------------"
echo "[INFO] Finish Crossplane Setup..."
echo "------------------------"

echo "------------------------"
echo "[INFO] Patching Argo CD for Crossplane..."
echo "------------------------"

# In order for Argo CD to track Application resources that contain Crossplane related objects, 
# configure it to use the annotation mechanism.
kubectl patch configmap argocd-cm -n argocd --patch-file /dev/stdin <<EOF
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
EOF

echo "------------------------"
echo "[INFO] Finishing Argo CD patching for Crossplane..."
echo "------------------------"


#################################
### KUBE-PROMETHEUS SETUP #######
#################################
echo "------------------------"
echo "[INFO] Setting up Kube-Prometheus..."
echo "------------------------"

kubectl create -f ../monitoring/prometheus-operator/kube-prometheus/manifests/setup
until kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
kubectl create -f manifests/
kubectl apply -f ../monitoring/prometheus-operator/prometheus-rbac.yaml
kubectl apply -f ../monitoring/prometheus-operator/prometheus-prometheus.yaml
kubectl apply -f ../monitoring/prometheus-operator/alertmanager-alertmanager.yaml

echo "------------------------"
echo "[INFO] Finishing Kube-Prometheus setup..."
echo "------------------------"

###################################
### Metric Server SETUP ###########
###################################
echo "------------------------"
echo "[INFO] Setting up Metric Server..."
echo "------------------------"

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server --version 3.13.0 \
-f ../metrics-server/values.yaml \
-n kube-system

echo "------------------------"
echo "[INFO] Finishing Metric Server setup..."
echo "------------------------"