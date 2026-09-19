# Architecture

## Runtime

```mermaid
flowchart LR
  spa[app-frontend<br/>Static Web App] --> bff[app-backend<br/>Container App]
  bff --> idp[identity-service<br/>Container App]
  bff --> apr[approval-service<br/>Container App]
  apr -->|ApprovalRequested / ApprovalDecided| q[(Storage Queues)]
  q --> wrk[worker-jobs<br/>KEDA-scaled Container App]
  wrk -->|escalations| apr
  apr --> cosmos[(Cosmos DB)]
  idp --> entra[Entra ID]
  spa -. auth .-> entra
  subgraph shared[platform-infrastructure per environment]
    law[Log Analytics + App Insights]
    kv[Key Vault]
    cae[Container Apps environment]
    cosmos
    q
  end
  acr[(ACR, shared across environments)] --> cae
```

## Resource naming

`{prefix}-{env}-{component}-{type}` with prefix `mrd`. Globally unique resources append a
per-environment `uniqueSuffix` from the variable group.

| Resource | Name |
| --- | --- |
| Resource groups | `rg-mrd-{env}-platform`, `rg-mrd-{env}-apps`, `rg-mrd-{env}-data` |
| Container Apps environment | `cae-mrd-{env}` |
| Key Vault | `kv-mrd-{env}-{suffix}` |
| Storage | `stmrd{env}{suffix}` |
| Cosmos | `cosmos-mrd-{env}-{suffix}` |
| App Insights | `appi-mrd-{env}` |
| Managed identity | `id-mrd-{env}-{service}` |
| Container App | `ca-mrd-{env}-{service}` |
| ACR (shared) | manifest `containerRegistry` |

## Ownership

| Area | Owner |
| --- | --- |
| Shared infrastructure, templates, libraries, base images | Platform Engineering |
| identity-service | Identity Team |
| approval-service, worker-jobs | Approvals Team |
| app-frontend, app-backend | Experience Team |
| Alerts, SLOs | SRE |
