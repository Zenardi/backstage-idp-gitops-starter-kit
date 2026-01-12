- [Installing the Kubernetes Ingestor Backend Plugin](#installing-the-kubernetes-ingestor-backend-plugin)
  - [Prerequisites](#prerequisites)
  - [Installation Steps](#installation-steps)
    - [1. Add the Packages](#1-add-the-packages)
    - [2. Add to Backend](#2-add-to-backend)
    - [3. Configure RBAC](#3-configure-rbac)
    - [4. Configure Plugin](#4-configure-plugin)
    - [5. Configure Git Integration](#5-configure-git-integration)
  - [Verification](#verification)
  - [Troubleshooting](#troubleshooting)
    - [Resource Discovery Issues](#resource-discovery-issues)
    - [Template Generation Problems](#template-generation-problems)
    - [API Creation Issues](#api-creation-issues)


The [@terasky/backstage-plugin-kubernetes-ingestor backend plugin](https://github.com/TeraSky-OSS/backstage-plugins/blob/main/plugins/kubernetes-ingestor/README.md) for Backstage is a catalog entity provider that creates catalog entities directly from Kubernetes resources. It has the ability to ingest by default all standard Kubernetes workload types, allows supplying custom GVKs, and has the ability to auto-ingest all Crossplane claims automatically as components. There are numerous annotations which can be put on the Kubernetes workloads to influence the creation of the component in Backstage. It also supports creating Backstage templates and registers them in the catalog for every XRD in your cluster for the Claim resource type. Currently, this supports adding via a PR to a GitHub/GitLab/Bitbucket/BitbucketCloud repo or providing a download link to the generated YAML without pushing to git. The plugin also generates API entities for all XRDs and defines the dependencies and relationships between all claims and the relevant APIs for easy discoverability within the portal.

# Installing the Kubernetes Ingestor Backend Plugin

This guide will help you install and set up the **Kubernetes Ingestor** backend plugin in your Backstage instance.

---

## Prerequisites

Before installing the plugin, ensure you have:

* A working Backstage backend instance.
* Access to Kubernetes clusters.
* Proper **RBAC** configuration.
* Git repository access (for template publishing).

---

## Installation Steps

### 1. Add the Packages

Install the required packages using **yarn**:

```bash
# Install the main plugin
yarn --cwd packages/backend add @terasky/backstage-plugin-kubernetes-ingestor

# Install the utilities package for template generation
yarn --cwd packages/backend add @terasky/backstage-plugin-scaffolder-backend-module-terasky-utils

```

### 2. Add to Backend

Modify your backend in `packages/backend/src/index.ts`:

```typescript
import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// Add the Kubernetes Ingestor plugin
backend.add(import('@terasky/backstage-plugin-kubernetes-ingestor'));

// Add required scaffolder modules for template generation
backend.add(import('@backstage/plugin-scaffolder-backend-module-github'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-gitlab'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-bitbucket'));
backend.add(import('@terasky/backstage-plugin-scaffolder-backend-module-terasky-utils'));

backend.start();

```

### 3. Configure RBAC

Set up the required **RBAC permissions** in your Kubernetes clusters to allow the ingestor to read resources:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: backstage-kubernetes-ingestor
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backstage-kubernetes-ingestor
subjects:
  - kind: ServiceAccount
    name: backstage-kubernetes-ingestor
    namespace: backstage
roleRef:
  kind: ClusterRole
  name: backstage-kubernetes-ingestor
  apiGroup: rbac.authorization.k8s.io

```

### 4. Configure Plugin

Add the following configuration to your `app-config.yaml` file:

```yaml
kubernetesIngestor:
  # Resource mapping configuration
  mappings:
    namespaceModel: 'cluster'
    nameModel: 'name-cluster'
    titleModel: 'name'
    systemModel: 'namespace'
    referencesNamespaceModel: 'default'

  # Component ingestion settings
  components:
    enabled: true
    ingestAsResources: false  # Set to true to create as Resource entities
    taskRunner:
      frequency: 10
      timeout: 600
    excludedNamespaces:
      - kube-public
      - kube-system
    customWorkloadTypes:
      - group: pkg.crossplane.io
        apiVersion: v1
        plural: providers

  # Crossplane integration
  crossplane:
    enabled: true
    claims:
      ingestAllClaims: true
      ingestAsResources: false  # Set to true for claims and XRs as Resources
    xrds:
      enabled: true
      ingestOnlyAsAPI: false  # Set to true to skip template generation
      publishPhase:
        allowedTargets: ['github.com', 'gitlab.com']
        target: github
        git:
          repoUrl: github.com?owner=org&repo=templates
          targetBranch: main
        allowRepoSelection: true
      taskRunner:
        frequency: 10
        timeout: 600

  # KRO integration (optional)
  kro:
    enabled: false
    instances:
      ingestAsResources: false  # Set to true for instances as Resources
    rgds:
      enabled: true
      ingestOnlyAsAPI: false  # Set to true to skip template generation

  # Generic CRD templates (optional)
  genericCRDTemplates:
    ingestOnlyAsAPI: false  # Set to true to skip template generation

  argoIntegration: false

```

### 5. Configure Git Integration

Set up environment variables to allow Backstage to interact with your Git provider:

```bash
export GITHUB_TOKEN=your-token
export GITLAB_TOKEN=your-token
export BITBUCKET_TOKEN=your-token

```

---

## Verification

After installation, verify the following:

* The plugin appears in your `package.json` dependencies.
* The backend starts without errors.
* Resources are being successfully ingested.
* Templates are being generated in the Scaffolder.
* APIs are being created.

---

## Troubleshooting

### Resource Discovery Issues

* **Check RBAC configuration:** Ensure the ServiceAccount has the correct permissions.
* **Verify cluster access:** Check if the Backstage backend can reach the Kubernetes API.
* **Review excluded namespaces:** Ensure your target resources aren't in `excludedNamespaces`.
* **Check task runner logs:** Look for error messages during the ingestion cycle.

### Template Generation Problems

* **Verify Git credentials:** Ensure the tokens exported in Step 5 have write access.
* **Check repository access:** Confirm the `repoUrl` in `app-config.yaml` is correct.
* **Review XRD configuration:** (For Crossplane users) Ensure XRDs are correctly defined.

### API Creation Issues

* **Verify Crossplane setup:** Ensure Crossplane is healthy in the cluster.
* **Review relationship mapping:** Check the `mappings` section in your config.


