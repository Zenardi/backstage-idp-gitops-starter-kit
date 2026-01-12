# Annotations

The plugin supports a rich set of annotations for customizing entity creation:

```
General Annotations:
  terasky.backstage.io/add-to-catalog: true/false
  terasky.backstage.io/exclude-from-catalog: true/false
  terasky.backstage.io/backstage-namespace: string
  terasky.backstage.io/owner: string

Namespace Annotations:
  terasky.backstage.io/system-type: string
  terasky.backstage.io/domain: string

Workload Resource Annotations:
  terasky.backstage.io/system: string
  terasky.backstage.io/source-code-repo-url: string
  terasky.backstage.io/source-branch: string
  terasky.backstage.io/techdocs-path: string
  terasky.backstage.io/kubernetes-label-selector: string
  terasky.backstage.io/component-type: string
  terasky.backstage.io/subcomponent-of: string
  terasky.backstage.io/lifecycle: string
  terasky.backstage.io/dependsOn: string
  terasky.backstage.io/providesApis: string
  terasky.backstage.io/consumesApis: string
  terasky.backstage.io/component-annotations: string
  terasky.backstage.io/links: string
  terasky.backstage.io/title: string
  terasky.backstage.io/name: string
  terasky.backstage.io/description: string
```