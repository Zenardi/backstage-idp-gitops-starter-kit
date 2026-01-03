- [Setup local environment for backstage IDP development](#setup-local-environment-for-backstage-idp-development)
- [Key Components:](#key-components)
- [Purpose and Workflow:](#purpose-and-workflow)
  - [**Setup Guide: Traefik on KIND (WSL Environment)**](#setup-guide-traefik-on-kind-wsl-environment)
    - [1. The `kind-config.yaml` File](#1-the-kind-configyaml-file)
    - [2. Installing Traefik](#2-installing-traefik)
    - [3. Deploying a Sample Application](#3-deploying-a-sample-application)
    - [4. Validation](#4-validation)
    - [Bonus: Accessing the Traefik Dashboard](#bonus-accessing-the-traefik-dashboard)
- [Installing ArgoCD](#installing-argocd)
- [Setup GitHub Runner on Local Kubernetes](#setup-github-runner-on-local-kubernetes)
- [Setting up Backstage](#setting-up-backstage)
  - [Setting GitHub OAuth](#setting-github-oauth)
    - [Backend Installation](#backend-installation)
    - [Adding the provider to the Backstage frontend](#adding-the-provider-to-the-backstage-frontend)
  - [Configure TechDocs](#configure-techdocs)


# Setup local environment for backstage IDP development
This project provides a comprehensive setup guide for creating a local Kubernetes development environment using KIND (Kubernetes in Docker), specifically tailored for working with the Backstage Internal Developer Portal (IDP). The setup focuses on establishing a functional cluster with Traefik as the ingress controller, enabling easy access to deployed applications via localhost.


# Key Components:
- KIND Cluster Configuration: Defines a single-node cluster named "backstage" with port mappings to expose Traefik's HTTP (port 80) and HTTPS (port 443) services directly on the host machine.
- Traefik Installation: Uses Helm to deploy Traefik as a NodePort service, pinned to container ports 30080 (HTTP) and 30443 (HTTPS) to align with the KIND configuration.
- Sample Applications: Includes one test deployment:
  - exampleapp.yaml: A simple http-echo pod with an Ingress resource routing traffic to exampleapp.local.
Validation Steps: Instructions for updating the hosts file (noted for Windows/WSL but adaptable to Linux), accessing applications, and optionally exposing the Traefik dashboard via port-forwarding.

# Purpose and Workflow:
The setup enables developers to quickly spin up a local Kubernetes environment for Backstage IDP development, testing ingress routing, and application deployments without requiring a full cloud-based cluster. It's designed for WSL environments but can be adapted for native Linux by adjusting host file configurations and port access. The guide emphasizes accessibility via localhost, making it ideal for iterative development and debugging of Backstage plugins or integrations.

---


## **Setup Guide: Traefik on KIND (WSL Environment)**

This guide sets up a local Kubernetes cluster using KIND within WSL, configuring Traefik as the Ingress Controller to be accessible via `localhost` on port 80.

### 1. The `kind-config.yaml` File

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

### 2. Installing Traefik

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

```

### 3. Deploying a Sample Application

We will deploy a simple "http-echo" pod and an Ingress resource to route traffic to it.

Create a file named `exampleapp.yaml`:

```yaml
# 1. Dummy Application
kind: Pod
apiVersion: v1
metadata:
  name: site-pod
  labels:
    app: site
spec:
  containers:
  - name: site-container
    image: hashicorp/http-echo
    args:
    - "-text=IT WORKS ON WSL!"
---
# 2. Service
kind: Service
apiVersion: v1
metadata:
  name: site-svc
spec:
  selector:
    app: site
  ports:
  - port: 5678
---
# 3. Ingress Resource
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: site-ingress
  annotations:
    # Optional if Traefik is the only controller, but good practice:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: exampleapp.local  # Ensure this is in your Windows /etc/hosts
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: site-svc
            port:
              number: 5678

```

**Apply the configuration:**

```bash
kubectl apply -f exampleapp.yaml

```

### 4. Validation

1. **Update Windows Hosts File:**
Ensure your Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`) points the domain to the local loopback address (not the WSL IP):
```text
127.0.0.1 exampleapp.local

```


2. **Access the Application:**
Open your browser or run curl in the terminal:
`http://exampleapp.local`
**Expected Output:** `IT WORKS ON WSL!`

### Bonus: Accessing the Traefik Dashboard

The dashboard is not exposed by default for security reasons. To access it:

1. **Port-forward the dashboard:**
```bash
kubectl port-forward -n traefik $(kubectl get pods -n traefik -o name) 9000:9000

```

2. **Open in browser:**
Go to `http://localhost:9000/dashboard/` (Note: the trailing slash `/` is required).


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

**Deploy and Configure ARC**
```bash
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller

helm upgrade --install --namespace ackgtions-runner-system --create-namespace\
  --set=authSecret.create=true\
  --set=authSecret.github_token="REPLACE_YOUR_TOKEN_HERE"\
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller
```

**Create the GitHub self hosted runners and configure to run against your repository.**

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

# Setting up Backstage
- https://backstage.io/docs/getting-started/#2-run-the-backstage-app
- https://backstage.io/docs/auth/github/provider


To setup backstage we will do it with docker. First step is to download node:18-bookworm-slim image. 
```bash
docker pull node:24-bookworm-slim
```

Create a directory like 'backstage-app'
Run the following command
```bash
docker run --rm -p 3000:3000 -p 7007 -ti -v backstage-app-fullpath-here:/app -w /app node:24-bookworm-slim bash

# Example
docker run --rm -p 3000:3000 -p 7007 -ti -v /home/developer/develop/backstage-idp-master-course/backstage-app:/app -w /app node:24-bookworm-slim bash
```

Inside the container let's now install backstage
```bash
npx @backstage/create-app@latest
```


After completing, you can start it up by running **'yarn start'**

In order to be able to access the backstage, inside the container edit the file under /app/backstage/app-config.local.yaml and follows
```bash
app:
  listen:
    host: 0.0.0.0
```

## Setting GitHub OAuth
Next create a new Oauth App in Github and generate a new client secret

Exit the container and replace AUTH_GITHUB_CLIENT_ID and AUTH_GITHUB_CLIENT_SECRET to yours. This is the new command to enter it.

```bash
docker run --rm \
-e AUTH_GITHUB_CLIENT_ID=Ov23lijEiQPGog0Aw6pb \
-e AUTH_GITHUB_CLIENT_SECRET=d4bf5791e3aa64eec3f5236b2db834c9cd7c15ae \
-p 3000:3000 -p 7007:7007 -ti \
-v /home/developer/develop/backstage-idp-master-course/backstage-app:/app \
-w /app node:24-bookworm-slim bash
```

Inside the container again, modify app-config.local.yaml as follows
```yaml
app:
  listen:
    host: 0.0.0.0

# Add this auth block
auth:
  environment: development
  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
        ## uncomment if using GitHub Enterprise
        # enterpriseInstanceUrl: ${AUTH_GITHUB_ENTERPRISE_INSTANCE_URL}
        ## uncomment to set lifespan of user session
        # sessionDuration: { hours: 24 } # supports `ms` library format (e.g. '24h', '2 days'), ISO duration, "human duration" as used in code
        signIn:
          resolvers:
            # See https://backstage.io/docs/auth/github/provider#resolvers for more resolvers
            - resolver: usernameMatchingUserEntityName
```

### Backend Installation
To add the provider to the backend we will first need to install the package by running this command:

from your Backstage root directory
```bash
yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-github-provider
```

Then we will need to add this line:

in packages/backend/src/index.ts
```ts
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-github-provider')); //add this line
```

### Adding the provider to the Backstage frontend

**Sign-In Configuration**
packages/app/src/App.tsx
```ts
import { githubAuthApiRef } from '@backstage/core-plugin-api'; //Add these two imports
import { SignInPage } from '@backstage/core-components';

const app = createApp({

  // Add this components block
  components: {
    SignInPage: props => (
      <SignInPage
        {...props}
        auto
        provider={{
          id: 'github-auth-provider',
          title: 'GitHub',
          message: 'Sign in using GitHub',
          apiRef: githubAuthApiRef,
        }}
      />
    ),
  },
  // ..
});
```
Since we configured usernameMatchingUserEntityName provider, we need to create a file under catalog/entities/users.yaml as below

```yaml
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: janelle.dawe # TODO: Replace by your Github user name
spec:
  profile:
    displayName: Janelle Dawe
    email: janelle-dawe@example.com
    picture: https://api.dicebear.com/7.x/avataaars/svg?seed=Leo&backgroundColor=transparent
  memberOf: [team-a]
```

Edit the app-config.local.yaml file and add catalog block as follows

```yaml
catalog:
  rules:
    - allow: [User, Component, System, API, Resource, Location]
  locations:
    - type: file
      target: /app/backstage/catalog/entities/users.yaml
```

## Configure TechDocs
- https://backstage.io/docs/features/techdocs/getting-started#setting-the-configuration

Edit app-config.local.yaml and append the following content
```yaml
techdocs:
  builder: 'local'
  publisher:
    type: 'local'
  generator:
    runIn: local
```

Install mkdocs on local container (generator is set to local so we need to install locally). Inside the same container you are running Backstage:
```bash
apt-get install -y python3 python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

export VIRTUAL_ENV=/opt/venv
python3 -m venv $VIRTUAL_ENV
export PATH="$VIRTUAL_ENV/bin:$PATH"

# Start the server again
yarn start
```