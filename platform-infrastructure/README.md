# meridian-platform-infrastructure

Subscription-scope Bicep for everything services share. One deployment per environment
(`shared`, `dev`, `test`, `prod`); `shared` holds the container registry only.

| Module | Creates |
| --- | --- |
| `bicep/main.bicep` | Resource groups (`platform`, `apps`, `data`), policy assignments, and the modules below |
| `modules/monitoring.bicep` | Log Analytics workspace + workspace-based Application Insights |
| `modules/identities.bicep` | One user-assigned managed identity per service |
| `modules/key-vault.bicep` | RBAC Key Vault, App Insights connection string secret, Secrets User for service identities, diagnostics |
| `modules/container-registry.bicep` | Shared ACR (`shared` only), admin disabled, diagnostics |
| `modules/acr-pull.bicep` | AcrPull for this environment's service identities on the shared ACR (cross-subscription scope) |
| `modules/container-apps-environment.bicep` | Container Apps environment wired to Log Analytics |
| `modules/storage.bicep` | Storage account (shared key disabled, TLS 1.2), Queue Data Contributor for producers/consumers |
| `modules/cosmos.bicep` | Serverless Cosmos DB (local auth disabled), `meridian` database, `approvals` container, data-plane RBAC |
| `modules/policy-assignments.bicep` | Allowed locations (deny), required `meridian:environment` tag on resource groups, storage public access audit |

Queues are **not** created here; `platform-libraries` owns queue names and creates them.
Container Apps are **not** created here; each service owns `infra/main.bicep` and references
these resources with `existing`.

## Pipeline

`azure-pipelines.yml` extends `pipelines/extends/infrastructure.yml@templates`:
Validate (bicep build + lint + PSRule + Trivy IaC) -> per environment: What-if (plain job,
artifact for approvers) -> Deploy (`deployment` job gated by environment checks). Environments
run in the order shared -> dev -> test -> prod; each What-if depends on Validate and on the
previous environment's Deploy, so a failed `shared` deploy stops `dev`. Every stage, `shared`
included, passes `uniqueSuffix=$(UniqueSuffix)`, which the bootstrap writes into the
`meridian-shared` variable group next to the per-environment groups.

## First-time prerequisites

The pipeline identity per environment is created **outside** this pipeline (it is the
identity the pipeline runs as):

```bash
pwsh scripts/New-PipelineIdentity.ps1 -Environment dev -SubscriptionId <id> -Location eastus2
```

It creates `id-mrd-<env>-pipelines` with Contributor and Role Based Access Control
Administrator on the subscription, then prints the values to paste into
`governance/environments/environments.json`.

## Local validation

```bash
az bicep build --file bicep/main.bicep --stdout > /dev/null
az deployment sub what-if --location eastus2 --template-file bicep/main.bicep --parameters bicep/params/dev.bicepparam --parameters uniqueSuffix=abc123
```
