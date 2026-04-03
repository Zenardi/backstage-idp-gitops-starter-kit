# Copilot Instructions

## Architecture Overview

This is a **local Kubernetes IDP (Internal Developer Portal) starter kit** built around Backstage, ArgoCD, and Crossplane, running on a KIND cluster. It has two deployment targets:

- **Local/WSL** (`kind/`): KIND cluster named `backstage`, with Traefik NodePort mapped to host ports 80/443.
- **Cloud (Hetzner)** (`.cloud-setup/`): Terraform-based k3s cluster on Hetzner Cloud with HAProxy, Cilium, Longhorn, and optional Rancher.

### Component Map

| Directory | Purpose |
|---|---|
| `kind/` | KIND cluster config (`kind-config.yaml`) and test manifests |
| `argocd/` | ArgoCD Helm values + GitOps `Application` manifests |
| `backstage/plugins/` | Custom Backstage plugins (`kubernetes-ingestor`, `api-docs`) |
| `traefik/` | Traefik ingress Helm values |
| `monitoring/prometheus-operator/` | Prometheus RBAC and custom resources |
| `metrics-server/` | Metrics Server Helm values and raw manifest |
| `github-runner/` | Actions Runner Controller manifests for in-cluster CI |
| `.cloud-setup/` | Terraform for Hetzner Cloud production cluster |
| `.devcontainer/` | Dev container definition; `postCreate.sh` fully automates local setup |

## Cluster Setup Commands

```bash
# Create KIND cluster
kind create cluster --config kind/kind-config.yaml

# Delete KIND cluster
kind delete cluster --name backstage
```

The KIND cluster maps container port `30080` → host `80` and `30443` → host `443`. Traefik is installed as a NodePort service on those ports.

## Installing Core Components

```bash
# Traefik
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade traefik traefik/traefik --install --create-namespace -n traefik -f traefik/values.yaml

# ArgoCD (local WSL)
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade argocd argo/argo-cd --version 9.2.3 --install --create-namespace -n argocd -f argocd/values.yaml

# ArgoCD (GitHub Codespaces – uses values-devcontainer.yaml, sets dynamic domain)
helm upgrade argocd argo/argo-cd --version 9.2.3 --install --create-namespace -n argocd \
  -f argocd/values-devcontainer.yaml \
  --set "server.ingress.hosts[0]=${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}" \
  --set "global.domain=${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"

# Metrics Server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server --version 3.13.0 \
  -f metrics-server/values.yaml -n kube-system
```

ArgoCD default admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

## Key Conventions

### Ingress / Hostnames
All services are exposed via Traefik using `.local` hostnames (e.g. `argocd.local`, `exampleapp.local`). In WSL you must add entries to `/etc/hosts` pointing to `127.0.0.1`. In Codespaces, hostnames are set dynamically using `$CODESPACE_NAME`.

### ArgoCD Helm values — two files
- `argocd/values.yaml` — for local WSL (hardcoded `argocd.local` hostname, `server.insecure: true`)
- `argocd/values-devcontainer.yaml` — for GitHub Codespaces (domain set at install time via `--set`)

### GitOps Application manifests
ArgoCD `Application` CRs live in `argocd/manifests/`. Example: `application-python-app.yaml` tracks `https://github.com/Zenardi/python-app.git` and deploys from a Helm chart at `charts/python-app`.

### Crossplane + ArgoCD integration
Crossplane requires two specific ArgoCD `argocd-cm` settings — both must be applied manually or via the values file:
1. `application.resourceTrackingMethod: annotation` — avoids label conflicts with Crossplane-managed resources.
2. Custom Lua health checks for `*.upbound.io/*` and `*.crossplane.io/*` — handles resources that may have no status (e.g. `ProviderConfig`, `ClusterProviderConfig`).
3. `resource.exclusions` to hide `ProviderConfigUsage` resources from the ArgoCD UI.

If managing many Crossplane CRDs, set `ARGOCD_K8S_CLIENT_QPS=300` on the application controller.

### Backstage `kubernetes-ingestor` plugin
The `backstage/plugins/kubernetes-ingestor/` plugin (`@terasky/backstage-plugin-kubernetes-ingestor`) auto-ingests standard Kubernetes workloads and **Crossplane claims** as Backstage components. It also generates Backstage `Template` entities from XRDs and `API` entities for each XRD. Requires RBAC (`ClusterRole`) granting read access to all relevant resource types, installed into the cluster where Backstage runs.

### Devcontainer automation
`.devcontainer/postCreate.sh` fully bootstraps the environment: installs `kind`, `kubectl`, `helm`, creates the KIND cluster from `kind/kind-config.yaml`, installs Traefik, ArgoCD (devcontainer variant), and Metrics Server, and starts port-forwards on `8888` (Traefik) and `8080` (ArgoCD).

### Terraform (`.cloud-setup/`)
Requires Terraform ≥ 1.8.0. Provisions a k3s cluster on Hetzner Cloud. Providers: `hcloud`, `github`, `ssh`, `local`, `cloudinit`. Modules: `host` (node provisioning) and `values_merger` (Helm values merging). Credentials are passed via environment variables (`HCLOUD_TOKEN`, etc.).
