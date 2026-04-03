---
name: azure-devops-agent-pool
description: >
  Guide for setting up a self-hosted Azure DevOps agent pool running as pods in the local
  KIND cluster, so Backstage pipeline templates can trigger jobs on it. Handles agent
  registration, Kubernetes Secret management, and deployment. Depends on the
  kind-cluster-setup skill.
argument-hint: "Agent Pool Name (e.g. \"kind-local\"), Azure DevOps Personal Access Token (e.g. \"<ADO_AGENT_PAT>\"), Azure DevOps Organization (e.g. \"my-org\" from https://dev.azure.com/my-org)"
---

## Parameters

| Parameter | Description |
|---|---|
| **Agent Pool Name** | Name of the self-hosted pool in Azure DevOps (e.g. `kind-local`) |
| **ADO_AGENT_PAT** | PAT with **Agent Pools (Read & Manage)** scope |
| **Azure DevOps Organization** | Organization name from `https://dev.azure.com/<Azure DevOps Organization>` (e.g. `my-org`) |

---

## Prerequisites

- The `backstage` KIND cluster is running (`kind-cluster-setup` skill)
- An Azure DevOps **organization URL** of the form `https://dev.azure.com/<Azure DevOps Organization>`
- A PAT with **Agent Pools (Read & Manage)** scope — generate at:
  `https://dev.azure.com/<Azure DevOps Organization>/_usersSettings/tokens`

Verify the cluster before proceeding:
```bash
kubectl cluster-info --context kind-backstage
```

---

## Step 1 — Create the Agent Pool in Azure DevOps

The pool must exist in Azure DevOps **before** the agent pods try to register.

### Option A — Azure DevOps UI

1. Go to `https://dev.azure.com/<Azure DevOps Organization>/_settings/agentpools`
2. Click **Add pool**
3. Pool type: **Self-hosted**
4. Name: `<Agent Pool Name>` (the value of your parameter)
5. ✅ Grant access permission to all pipelines
6. Click **Create**

### Option B — Azure CLI

```bash
# Install the Azure DevOps extension if not already installed
az extension add --name azure-devops

az devops configure --defaults organization=https://dev.azure.com/<Azure DevOps Organization>

az pipelines pool create \
  --name "<Agent Pool Name>" \
  --pool-type private \
  --org https://dev.azure.com/<Azure DevOps Organization>
```

---

## Step 2 — Create the Kubernetes Secret

The secret holds all sensitive configuration. **Never commit this to git.**

```bash
kubectl create namespace azure-devops-agents --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic azure-devops-agent-secret \
  --namespace azure-devops-agents \
  --from-literal=AZP_URL=https://dev.azure.com/<Azure DevOps Organization> \
  --from-literal=AZP_TOKEN=<ADO_AGENT_PAT> \
  --from-literal=AZP_POOL="<Agent Pool Name>" \
  --save-config
```

Verify:
```bash
kubectl get secret azure-devops-agent-secret -n azure-devops-agents
```

---

## Step 3 — Build and Load the Agent Image

The Azure Pipelines agent image must be built locally and loaded into the KIND cluster, because
`vstsagentpackage.azureedge.net` (the official download CDN) may not be resolvable from within
rootless Docker build contexts.

### Step 3a — Download the agent tarball on the host

```bash
# Get the latest agent version download URL
AGENT_URL=$(curl -fsSL https://github.com/microsoft/azure-pipelines-agent/releases/download/v4.270.0/assets.json \
  | python3 -c "import sys,json; a=json.load(sys.stdin); print(next(x['downloadUrl'] for x in a if 'linux-x64' in x['name'] and x['name'].endswith('.tar.gz')))")

curl -fsSL "$AGENT_URL" -o azure-devops-agents/agent.tar.gz
```

### Step 3b — Build the Docker image

```bash
cd <repo-root>
docker build -t azure-devops-agent:latest azure-devops-agents/
```

### Step 3c — Load the image into the KIND cluster

```bash
kind load docker-image azure-devops-agent:latest --name backstage
```

The `azure-devops-agents/deployment.yaml` already uses `image: azure-devops-agent:latest` with
`imagePullPolicy: Never`, so no registry is needed.

---

## Step 4 — Deploy the Agent Pods

The deployment manifest is already committed at `azure-devops-agents/deployment.yaml`. Apply it:

```bash
cd <repo-root>
kubectl apply -f azure-devops-agents/namespace.yaml
kubectl apply -f azure-devops-agents/deployment.yaml
```

Watch the pods come up:
```bash
kubectl rollout status deployment/azure-devops-agent -n azure-devops-agents
kubectl get pods -n azure-devops-agents -w
```

Each pod automatically registers itself with Azure DevOps on startup using its **pod name**
as the agent name.

---

## Step 4 — Verify Agents in Azure DevOps

1. Go to `https://dev.azure.com/<Azure DevOps Organization>/_settings/agentpools`
2. Click the `<Agent Pool Name>` pool
3. Under the **Agents** tab, you should see 2 agents with status **Online**

Or use the CLI:
```bash
az pipelines agent list \
  --pool-name "<Agent Pool Name>" \
  --org https://dev.azure.com/<Azure DevOps Organization>
```

---

## Step 5 — Configure Backstage Pipeline Templates

In your Backstage scaffolder templates, reference the pool by name in your pipeline YAML:

```yaml
# azure-pipelines.yml
pool:
  name: <Agent Pool Name>

steps:
  - script: echo "Running on KIND cluster agent"
```

---

## Scaling Agents

Change the number of replicas to add or remove agents:

```bash
# Scale up to 4 agents
kubectl scale deployment azure-devops-agent -n azure-devops-agents --replicas=4

# Or edit deployment.yaml and re-apply:
# spec.replicas: 4
kubectl apply -f azure-devops-agents/deployment.yaml
```

Each replica registers as a separate agent in the pool (named by pod name), so Azure DevOps
can run multiple jobs in parallel.

---

## Updating the PAT

When the PAT expires, update the secret and restart the pods:

```bash
kubectl create secret generic azure-devops-agent-secret \
  --namespace azure-devops-agents \
  --from-literal=AZP_URL=https://dev.azure.com/<Azure DevOps Organization> \
  --from-literal=AZP_TOKEN=<new-PAT> \
  --from-literal=AZP_POOL="<Agent Pool Name>" \
  --save-config --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/azure-devops-agent -n azure-devops-agents
```

---

## Teardown

To remove agents and deregister them from Azure DevOps:

```bash
# Scale to 0 — each pod gracefully deregisters before terminating
kubectl scale deployment azure-devops-agent -n azure-devops-agents --replicas=0

# Full removal
kubectl delete namespace azure-devops-agents
```

---

## Troubleshooting

### Pods stuck in `ImagePullBackOff`

The agent image is built locally and loaded into KIND — it is **not** pulled from a registry.
If you see `ImagePullBackOff`, the image was not loaded into the cluster. Re-run step 3c:
```bash
kind load docker-image azure-devops-agent:latest --name backstage
kubectl rollout restart deployment/azure-devops-agent -n azure-devops-agents
```

### Agent pods crash with "Must not run with sudo"

The Azure Pipelines agent refuses to run as root. The `Dockerfile` creates a non-root `agent`
user and switches to it via `USER agent`. If you rebuild the image, ensure this is present.

### Agents not appearing in Azure DevOps
Check pod logs for registration errors:
```bash
kubectl logs -n azure-devops-agents -l app=azure-devops-agent --tail=50
```

Common causes:
- **Wrong AZP_URL** — must be `https://dev.azure.com/<org>`, no trailing slash
- **PAT lacks permissions** — needs **Agent Pools (Read & Manage)** scope
- **Pool doesn't exist** — create it in Azure DevOps UI first (step 1)
- **PAT has expired** — generate a new one (see "Updating the PAT" above)

### Agents show as Offline after pod restart
This is normal — old agent entries linger in Azure DevOps. They are cleaned up automatically
after 30 days, or you can delete them manually in the Azure DevOps UI.

### Pipeline jobs stay queued ("No agents available")
- Verify agents are **Online** in the Azure DevOps pool UI
- Confirm the pipeline `pool.name` exactly matches the pool name (case-sensitive)
- Check if the pool has **pipeline permissions**: in Azure DevOps UI → pool → Security

### Agent pod crashes during a job (OOMKilled)
The deployment sets a 4Gi memory limit. For memory-heavy builds, increase the limit:
```bash
kubectl edit deployment azure-devops-agent -n azure-devops-agents
# Change resources.limits.memory to e.g. "8Gi"
```

### Running Docker builds inside agent pods
By default the agents cannot build Docker images. To enable **Docker-in-Docker**:
```bash
# Add a DinD sidecar — edit deployment.yaml and add under spec.template.spec.containers:
#   - name: dind
#     image: docker:dind
#     securityContext:
#       privileged: true
#     env:
#       - name: DOCKER_TLS_CERTDIR
#         value: ""
#     volumeMounts:
#       - name: docker-sock
#         mountPath: /var/run
# Add under spec.template.spec.volumes:
#   - name: docker-sock
#     emptyDir: {}
# Add to the agent container env:
#   - name: DOCKER_HOST
#     value: tcp://localhost:2375
```
