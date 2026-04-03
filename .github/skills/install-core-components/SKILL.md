---
name: install-core-components
description: >
  Guide for installing the core platform components — Traefik, ArgoCD, Metrics Server, and
  Prometheus Operator (kube-prometheus) — into the local KIND cluster for the
  backstage-idp-gitops-starter-kit. Use this skill when asked to install, upgrade, or
  troubleshoot any of these components after the KIND cluster is up. Depends on the
  kind-cluster-setup skill.
---

## Prerequisites

The `backstage` KIND cluster must already be running. Verify before proceeding:

```bash
kubectl cluster-info --context kind-backstage
kubectl get nodes --context kind-backstage
```

If the cluster is not up, run the `kind-cluster-setup` skill first.

All commands below assume you are in the **git root** of the repository and `kubectl` is
pointing at the `kind-backstage` context:

```bash
kubectl config use-context kind-backstage
```

---

## ⚠️ Pre-flight: inotify limits (rootless Docker)

**Always check this first.** On rootless Docker, all container processes share the host user's
inotify quota. With the default limit of 128, kube-proxy and other system pods will crash with
`too many open files` (EMFILE) as soon as enough other processes (VS Code, browser, etc.) are running.

Check current usage vs. limit:
```bash
cat /proc/sys/fs/inotify/max_user_instances
```

If the value is `128` (the default), increase it **before** installing anything:
```bash
# Temporary fix (takes effect immediately, lost on reboot)
pkexec sysctl -w fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288

# Persist across reboots
echo -e 'fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288' \
  | sudo tee /etc/sysctl.d/99-kind.conf
```

> **Note:** Use `pkexec` rather than `sudo` if you're in a desktop session — `pkexec` uses
> polkit (GUI auth) and doesn't require a terminal password prompt.

---

## Full Stack Install Order

Always install in this order to satisfy dependencies:

1. **Prometheus CRDs** — must exist before Traefik and ArgoCD (both create ServiceMonitors)
2. **Traefik** — ingress controller; other services create Ingress objects at install time
3. **ArgoCD** — uses Traefik ingress; `argocd/values.yaml` creates ServiceMonitors in `monitoring`
4. **Metrics Server** — independent, but needed for HPA
5. **Prometheus Operator** — full stack after CRDs + namespace are already present

---

## 1. Prometheus CRDs + namespace (install first)

The `monitoring` namespace and Prometheus CRDs **must exist** before Traefik and ArgoCD are
installed, because their Helm charts create `ServiceMonitor` resources at install time.

```bash
kubectl create -f monitoring/prometheus-operator/kube-prometheus/manifests/setup

# Wait until ServiceMonitor CRD is ready
until kubectl get servicemonitors --all-namespaces &>/dev/null; do
  echo "Waiting for CRDs..."; sleep 2
done
echo "CRDs ready"
```

---

## 2. Traefik (Ingress Controller)

> **Known issue:** `traefik/values.yaml` has `secretResourceNames: []` under `rbac` which fails
> schema validation. Always pass `--skip-schema-validation`.

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade traefik traefik/traefik \
  --install --create-namespace -n traefik \
  --skip-schema-validation \
  -f traefik/values.yaml
```

`traefik/values.yaml` configures Traefik as a **NodePort** service on ports `30080` (HTTP)
and `30443` (HTTPS), which map to host ports 80/443 via the KIND port mappings.

Verify:
```bash
kubectl get svc -n traefik
kubectl get pods -n traefik
```

---

## 3. ArgoCD

> **Known issue:** `argocd/values.yaml` creates `ServiceMonitor` and `PrometheusRule` resources
> in the `monitoring` namespace. The namespace **must already exist** (step 1 above) or the
> helm install will fail with `namespaces "monitoring" not found`.

> **Known issue:** The `argocd-redis-secret-init` pre-install Job can take several minutes on
> KIND. Always use `--timeout 10m`.

### Local WSL

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade argocd argo/argo-cd --version 9.2.3 \
  --install --create-namespace -n argocd \
  --timeout 10m \
  -f argocd/values.yaml
```

`argocd/values.yaml` uses the hardcoded hostname `argocd.local` and `server.insecure: true`.
Add `127.0.0.1 argocd.local` to `/etc/hosts` to access it.

### GitHub Codespaces

```bash
helm upgrade argocd argo/argo-cd --version 9.2.3 \
  --install --create-namespace -n argocd \
  --timeout 10m \
  -f argocd/values-devcontainer.yaml \
  --set "server.ingress.hosts[0]=${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}" \
  --set "global.domain=${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
```

Get the admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

Verify:
```bash
kubectl get pods -n argocd
```

---

## 4. Metrics Server

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade metrics-server metrics-server/metrics-server --version 3.13.0 \
  --install \
  -f metrics-server/values.yaml \
  -n kube-system
```

`metrics-server/values.yaml` sets `--kubelet-insecure-tls` (required for KIND) and
`insecureSkipTLSVerify: true`.

Verify (may take ~30s):
```bash
kubectl top nodes
kubectl top pods -A
```

---

## 5. Prometheus Operator (kube-prometheus)

CRDs and namespace were already applied in step 1. Now install the full stack:

### Step 1 — Install all remaining manifests

```bash
kubectl create -f monitoring/prometheus-operator/kube-prometheus/manifests/
```

> `AlreadyExists` errors for CRDs are expected and harmless if this is a reinstall.
> If you see "no kind" errors, wait 10s and retry.

### Step 2 — Apply custom RBAC, Prometheus, and AlertManager resources

```bash
kubectl apply -f monitoring/prometheus-operator/prometheus-rbac.yaml
kubectl apply -f monitoring/prometheus-operator/prometheus-prometheus.yaml
kubectl apply -f monitoring/prometheus-operator/alertmanager-alertmanager.yaml
```

Verify:
```bash
kubectl get pods -n monitoring
```

---

## Upgrading Components

```bash
# Traefik (--skip-schema-validation always required)
helm upgrade traefik traefik/traefik -n traefik \
  --skip-schema-validation -f traefik/values.yaml

# ArgoCD
helm upgrade argocd argo/argo-cd --version 9.2.3 \
  -n argocd --timeout 10m -f argocd/values.yaml

# Metrics Server
helm upgrade metrics-server metrics-server/metrics-server --version 3.13.0 \
  -f metrics-server/values.yaml -n kube-system
```

---

## Troubleshooting

### Pods in CrashLoopBackOff with "too many open files"

Root cause: `fs.inotify.max_user_instances` limit exhausted (rootless Docker). See the
pre-flight section above. After raising the limit, delete the crashing pods so they restart
fresh with working file descriptors:

```bash
pkexec sysctl -w fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288
kubectl rollout restart daemonset/kube-proxy -n kube-system
# Delete any other pods still in CrashLoopBackOff:
kubectl delete pod -n <namespace> <pod-name>
```

### ArgoCD install fails with "namespaces monitoring not found"

`argocd/values.yaml` creates ServiceMonitors in the `monitoring` namespace. Run step 1
(Prometheus CRDs + namespace) before installing ArgoCD.

### ArgoCD helm release stuck in `pending-upgrade`

A previous failed install left the release in a broken state. Roll back and retry:

```bash
helm rollback argocd -n argocd
helm upgrade argocd argo/argo-cd --version 9.2.3 \
  -n argocd --timeout 10m -f argocd/values.yaml
```

### ArgoCD pods fail with `secret "argocd-redis" not found`

The `argocd-redis-secret-init` pre-install Job didn't complete (e.g. networking was broken).
Trigger a fresh install — rolling back and upgrading re-runs the pre-install hook:

```bash
helm rollback argocd -n argocd
helm upgrade argocd argo/argo-cd --version 9.2.3 \
  -n argocd --timeout 10m -f argocd/values.yaml
```

### Metrics Server crashes with `dial tcp 10.96.0.1:443: i/o timeout`

kube-proxy was down when the pod started, so it has no route to the cluster IP. Delete the
pod so it restarts after kube-proxy is healthy:

```bash
kubectl delete pod -n kube-system -l k8s-app=metrics-server
```

### Traefik schema validation error

Always use `--skip-schema-validation` — see step 2 above.

### Prometheus CRD race condition

If `kubectl create -f manifests/` fails with "no kind" errors, wait and retry:
```bash
kubectl create -f monitoring/prometheus-operator/kube-prometheus/manifests/
```

### ArgoCD + Crossplane resource tracking

If using Crossplane, patch `argocd-cm` after ArgoCD is installed:
```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"application.resourceTrackingMethod":"annotation"}}'
```

### ArgoCD pods not starting (general)

```bash
kubectl describe pods -n argocd
# repoServer has a 60s initialDelaySeconds — wait at least 2 minutes before diagnosing
```

### Metrics Server `unable to fully collect metrics`

Ensure `--kubelet-insecure-tls` is set (it is in `metrics-server/values.yaml`):
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server
```
