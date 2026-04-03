---
name: kind-cluster-setup
description: >
  Guide for creating, verifying, and tearing down the local KIND (Kubernetes in Docker) cluster
  for the backstage-idp-gitops-starter-kit. Use this skill when asked to create or recreate the
  KIND cluster, check cluster status, or troubleshoot cluster setup issues.
---

## Cluster Definition

The cluster is defined in `kind/kind-config.yaml`. Key properties:
- **Cluster name:** `backstage`
- **Port mappings:** container `30080` → host `80` (HTTP), container `30443` → host `443` (HTTPS)
- These ports are where Traefik NodePort service listens, making apps accessible at `localhost`.

## Creating the Cluster

Always run from the **git root** of the repository:

```bash
kind create cluster --name backstage --config kind/kind-config.yaml
```

> **Note:** kind v0.20+ ignores the `name:` field inside the config YAML — always pass `--name backstage` explicitly on the command line.

Verify the cluster is up:

```bash
kubectl cluster-info --context kind-backstage
kubectl get nodes
```

## Deleting the Cluster

```bash
kind delete cluster --name backstage
```

## Prerequisites

Ensure these tools are installed before creating the cluster:

```bash
kind version        # kind v0.20+
kubectl version     # kubectl v1.28+
docker info         # Docker must be running
```

## After Cluster Creation

Once the cluster is up, install core components in this order:

### 1. Traefik (Ingress Controller)
```bash
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm upgrade traefik traefik/traefik --install --create-namespace -n traefik -f traefik/values.yaml
```

### 2. ArgoCD
```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade argocd argo/argo-cd --version 9.2.3 --install --create-namespace -n argocd -f argocd/values.yaml
```

### 3. Metrics Server
```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server --version 3.13.0 \
  -f metrics-server/values.yaml -n kube-system
```

Get ArgoCD admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

## /etc/hosts (WSL only)

Add entries for `.local` hostnames so apps are reachable at `localhost`:

```
127.0.0.1  argocd.local
127.0.0.1  exampleapp.local
```

## Troubleshooting

**Port 80/443 already in use:**
Check for processes on the host ports before creating the cluster:
```bash
sudo lsof -i :80
sudo lsof -i :443
```

**Cluster already exists:**
```bash
kind get clusters   # list existing clusters
kind delete cluster --name backstage   # delete before recreating
```

**Docker not running:**
```bash
sudo systemctl start docker   # or start Docker Desktop
```

**Nodes NotReady:**
```bash
kubectl describe node | grep -A5 Conditions
```
Usually resolves in ~30s. If persistent, check Docker resource limits.
