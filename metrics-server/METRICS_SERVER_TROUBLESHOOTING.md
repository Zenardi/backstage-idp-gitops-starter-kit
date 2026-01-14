# Metrics-Server Readiness Probe Failure - Troubleshooting Guide

## Problem
Metrics-server pod fails to start with the following warning:
```
Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 500
```

The HPA shows `cpu: <unknown>` instead of actual CPU values:
```
react-app-1-hpa  Deployment/react-app-1  cpu: <unknown>/70%  1  5  2  152m
```

## Root Cause
The readiness probe HTTP 500 error indicates that **metrics-server cannot communicate securely with the kubelet on worker nodes**. This happens because:

1. **TLS Certificate Verification Failure**: Metrics-server tries to connect to kubelets using HTTPS with certificate verification enabled by default
2. **Self-Signed Certificates**: Kubernetes clusters (especially local/development ones like Kind or Minikube) use self-signed certificates that metrics-server can't verify
3. **Missing Kubelet API Access**: The metrics-server can't reach the kubelet API endpoint to scrape metrics

## Why This Matters
- **HPA requires metrics**: Horizontal Pod Autoscaler needs CPU/memory metrics from metrics-server to make scaling decisions
- **No metrics = no auto-scaling**: Without metrics-server working, HPAs remain frozen and can't scale your pods based on demand
- **Cluster-wide issue**: This affects all applications using HPA, not just one

## Solution Applied
We patched the metrics-server deployment with the `--kubelet-insecure-tls` flag:

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value":"--kubelet-insecure-tls"}
]'
```

### What This Does
- **`--kubelet-insecure-tls`**: Disables TLS certificate verification when connecting to kubelets
- **`-n kube-system`**: Targets the system namespace where metrics-server runs
- **`--type='json'`**: Uses JSON patch format to modify the deployment
- **`/spec/template/spec/containers/0/args/-`**: Adds the flag to the container arguments

## Verification Steps
After applying the patch:

```bash
# 1. Check if pod is ready
kubectl get pod -n kube-system | grep metrics-server

# 2. Verify metrics are being collected
kubectl top nodes
kubectl top pods -n <your-namespace>

# 3. Confirm HPA is working
kubectl get hpa -n <your-namespace>
# Should show actual CPU values, not <unknown>
```

## Prevention for Future Deployments
Include this configuration in your metrics-server installation YAML:

```yaml
args:
- --kubelet-insecure-tls
- --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
```

## Important Notes
- **Development Environments Only**: The `--kubelet-insecure-tls` flag should only be used in development/testing environments
- **Production Security**: In production clusters with proper certificate management, this flag should not be needed
- **Metrics Take Time**: After fixing metrics-server, wait 1-2 minutes for metrics to appear in your HPA status
