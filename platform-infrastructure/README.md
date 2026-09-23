# meridian-platform-infrastructure

Subscription-scope Bicep for everything services share. One deployment per environment
(`shared`, `dev`, `test`, `prod`). `shared` has no `apps` or `data` resource group and no
per-service resources; it holds the container registry, a Consumption Container Apps
environment and a Key Vault for the self-hosted agent pool, and, behind a flag, the two
Container Apps jobs that run it (see "Self-hosted agent pool" below).

| Module | Creates |
| --- | --- |
| `bicep/main.bicep` | Resource groups (`platform`, `apps`, `data`), policy assignments, and the modules below |
| `modules/monitoring.bicep` | Log Analytics workspace + workspace-based Application Insights |
| `modules/identities.bicep` | One user-assigned managed identity per service; also creates `shared`'s agent-pool identity (`id-mrd-shared-agents`) |
| `modules/key-vault.bicep` | RBAC Key Vault, Secrets User for its reader identities, diagnostics; the App Insights connection string secret is optional (`createAppInsightsSecret`, default `true`) so the `shared` agent-pool vault can skip it |
| `modules/container-registry.bicep` | Shared ACR (`shared` only), admin disabled, diagnostics |
| `modules/acr-pull.bicep` | AcrPull for this environment's service identities on the shared ACR (cross-subscription scope); also grants it to the `shared` agent-pool identity |
| `modules/container-apps-environment.bicep` | Container Apps environment wired to Log Analytics, one per environment including `shared` |
| `modules/container-apps-jobs.bicep` | `shared` only, behind `agentPoolEnabled`: the two self-hosted Azure Pipelines agent jobs |
| `modules/storage.bicep` | Storage account (shared key disabled, TLS 1.2), Queue Data Contributor for producers/consumers |
| `modules/cosmos.bicep` | Serverless Cosmos DB (local auth disabled), `meridian` database, `approvals` container, data-plane RBAC |
| `modules/policy-assignments.bicep` | Allowed locations (deny), required `meridian:environment` tag on resource groups, storage public access audit |

Queues are **not** created here; `platform-libraries` owns queue names and creates them.
Container Apps for a service are **not** created here; each service owns `infra/main.bicep`
and references these resources with `existing`. The self-hosted agent pool's two Container
Apps *jobs* are the one exception: a platform resource, not a service, so they are created
here.

## Self-hosted agent pool (`shared`, opt-in)

`shared` always deploys `cae-mrd-shared` (Consumption Container Apps environment on
`log-mrd-shared`), `kv-mrd-shared-<uniqueSuffix>` (no secrets declared by this template) and
`id-mrd-shared-agents` (AcrPull on `acrmrdshared`, Key Vault Secrets User on that vault), so
the owner has somewhere to store the pool's PAT before turning the pool on.

Behind `agentPoolEnabled` (`false` by default; set in `bicep/params/shared.bicepparam`), two
more resources deploy:

| Job | Trigger | Purpose |
| --- | --- | --- |
| `caj-mrd-shared-agent` | Event (KEDA `azure-pipelines` scaler polling pool `meridian-agents`, one execution at a time) | Runs one pipeline job per container, 2 vCPU / 4 GiB |
| `caj-mrd-shared-agent-placeholder` | Manual | Started once by `tooling/Initialize-AgentPool.ps1` to keep one agent registered offline, so the pool is never empty |

Parameters:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `agentPoolEnabled` | `false` | Deploys the two jobs above. The environment, identity, ACR pull and vault deploy regardless. |
| `agentImageTag` | `1.0.1` | Tag of `acrmrdshared.azurecr.io/agents/azp-agent` the jobs run (see `containers/agents/azp-agent/`) |

Outputs (all empty string outside `shared`): `agentPoolKeyVaultName`, `agentPoolPatSecretUri`
(the secret URI to write `azdo-agent-pat` to), `agentPoolEnvironmentName`, `agentJobName`,
`agentPlaceholderJobName`.

Turning it on, in order:

1. Deploy `shared` once so the vault exists.
2. Owner stores the PAT: `az keyvault secret set --vault-name kv-mrd-shared-<uniqueSuffix>
   --name azdo-agent-pat --value <pat>`.
3. Flip `agentPoolEnabled` to `true` in `bicep/params/shared.bicepparam`.
4. Deploy `shared` again so the two jobs and their `secretRef` wire up.
5. `pwsh tooling/Initialize-AgentPool.ps1 -EnsurePool -AuthorizeAllPipelines -RegisterPlaceholder`
   (see `tooling/README.md` for what each switch does).

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
