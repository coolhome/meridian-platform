# Handoff: state of the Meridian rollout (2026-09-19)

Read this first when continuing in a new session. Everything below was verified in the
session that wrote it unless marked *assumed*.

## Where things stand

| Area | State |
| --- | --- |
| Monorepo scaffold | Complete and committed on `main` (see `git log`). All .NET builds and 24 tests pass, SPA lint/test/build pass, all Bicep compiles, boundary check passes. |
| Cost posture | ADR 0007 applied: scale to zero everywhere, LRS, Basic ACR, Free SWA, 30-day logs. Approx. $60 to $80 per month for all environments. |
| GitHub | Repo `coolhome/meridian-platform` **does not exist yet**. `gh` is logged in as `coolhome` with `repo` and `workflow` scopes, so `gh repo create coolhome/meridian-platform --private --source . --push` will work. `.github/CODEOWNERS` still says `@CHANGE-ME/...` teams. |
| Azure DevOps | Nothing created. Org is `https://dev.azure.com/coolhome` (existing projects: Test, DevOpsTesting, food-butler, AI-GoWild). `repos.manifest.json` still says `CHANGE-ME`; set `azureDevOps.organizationUrl` to the coolhome URL and `github.repository` to `coolhome/meridian-platform`. |
| Azure | Nothing deployed. Logged in as PJAlva1@hotmail.com, subscription **Platform** (`ac39dedd-f5fd-404c-9013-07575f55a6ec`), tenant `c8162553-8d13-43aa-8bd6-a254ccbb9a33`, region East US 2 available. |
| Local stack | Not started. Docker and Azurite are not installed; use `npx --yes azurite`. Producers and the worker now create queues on demand so Azurite needs no setup. SPA dev server runs via `.claude/launch.json` (`npm run dev` on 5173) with `app-frontend/.env.development` selecting header auth. |

## Authentication findings that shape the next steps

1. The `az devops` CLI extension authenticates to `coolhome` with a **PAT stored in Windows
   Credential Manager** (`azdevops-cli:https://dev.azure.com/coolhome`). CLI-based parts of the
   tooling therefore work with no `AZDO_PAT` set.
2. A raw Entra bearer token (`az account get-access-token --resource 499b84ac-...`) is
   **rejected** by the org (`TF400813`, MSA-owned org versus AAD tenant identity). So the REST
   parts of `tooling/lib/Meridian.Ado.psm1` (`Invoke-AdoRest`: environments, checks, pipeline
   permissions, feeds, Key Vault variable groups, general settings, identities) need one of:
   * a PAT exported as `AZDO_PAT` (simplest; scopes are printed by the module when missing), or
   * a refactor of `Invoke-AdoRest` to fall back to `az devops invoke --area ... --resource ...`
     when no PAT is present (uses the stored credential; note `--api-version` must be a plain
     number such as `7.1`, the value `7.1-preview.1` broke argument parsing once).
3. `git push` to Azure Repos in `Sync-ToAzureRepos.ps1` also uses the PAT via
   `http.extraheader`; with no PAT, `git` will fall back to Git Credential Manager, which may
   prompt interactively.
4. Hosted parallel-job capacity for the org is **unknown**; the `resourceusage` query failed on
   argument parsing. If pipelines sit in "waiting for an agent", request the free grant at
   https://aka.ms/azpipelines-parallelism-request or add a self-hosted agent.

## Exact next steps, in order

```bash
# 0. point the manifest at the real org and repo
#    repos.manifest.json: azureDevOps.organizationUrl = https://dev.azure.com/coolhome
#                         github.repository            = coolhome/meridian-platform

# 1. local full stack (five terminals or background jobs)
npx --yes azurite --silent --location .azurite --skipApiVersionCheck
ASPNETCORE_ENVIRONMENT=Development dotnet identity-service/src/Meridian.Identity.Api/bin/Release/net10.0/Meridian.Identity.Api.dll --urls http://localhost:5100
ASPNETCORE_ENVIRONMENT=Development Messaging__Provider=StorageQueue Messaging__ConnectionString=UseDevelopmentStorage=true dotnet approval-service/src/Meridian.Approval.Api/bin/Release/net10.0/Meridian.Approval.Api.dll --urls http://localhost:5200
ASPNETCORE_ENVIRONMENT=Development dotnet app-backend/src/Meridian.Bff/bin/Release/net10.0/Meridian.Bff.dll --urls http://localhost:5000
ASPNETCORE_ENVIRONMENT=Development dotnet worker-jobs/src/Meridian.Worker/bin/Release/net10.0/Meridian.Worker.dll --urls http://localhost:5300
# SPA: npm run dev in app-frontend (already wired in .claude/launch.json), sign in as alice, then as bob with Approver

# 2. GitHub
gh repo create coolhome/meridian-platform --private --source . --push
gh secret set AZDO_PAT            # after creating the PAT below
gh variable set MERIDIAN_ADO_ORG_URL --body https://dev.azure.com/coolhome
gh variable set MERIDIAN_ADO_PROJECT --body Meridian

# 3. Azure DevOps control plane (needs AZDO_PAT exported, see findings)
pwsh ./tooling/Initialize-AzureDevOps.ps1 -SkipServiceConnections
pwsh ./tooling/Publish-Platform.ps1
pwsh ./tooling/Initialize-AzureDevOps.ps1 -SkipServiceConnections   # second pass: required-template checks now that the templates repo exists

# 4. Azure (shared + dev only, about $25/month)
pwsh platform-infrastructure/scripts/New-PipelineIdentity.ps1 -Environment shared -SubscriptionId ac39dedd-f5fd-404c-9013-07575f55a6ec -Location eastus2
pwsh platform-infrastructure/scripts/New-PipelineIdentity.ps1 -Environment dev    -SubscriptionId ac39dedd-f5fd-404c-9013-07575f55a6ec -Location eastus2
#    paste the printed values into governance/environments/environments.json (shared, dev), pick uniqueSuffix values
pwsh ./tooling/Initialize-AzureDevOps.ps1            # creates WIF service connections, prints the federated-credential commands; run them
#    then run pipelines in this order: platform-infrastructure-cicd, containers-base-images,
#    platform-libraries-cicd, identity-service-cicd, approval-service-cicd, app-backend-cicd,
#    worker-jobs-cicd, app-frontend-cicd, observability-cicd
#    or, without waiting on agents, deploy directly:
az deployment sub create --location eastus2 --template-file platform-infrastructure/bicep/main.bicep --parameters platform-infrastructure/bicep/params/shared.bicepparam --parameters uniqueSuffix=<suffix>
az deployment sub create --location eastus2 --template-file platform-infrastructure/bicep/main.bicep --parameters platform-infrastructure/bicep/params/dev.bicepparam    --parameters uniqueSuffix=<suffix>
```

Placeholders still in the tree: `CHANGE-ME` in `repos.manifest.json`, `.github/CODEOWNERS`,
service `nuget.config` feed URLs, `app-frontend/.npmrc`, `appsettings.json` AzureAd sections,
`governance/policies/branch-policy-profiles.json` author-email domain, and all-zero GUIDs in
`governance/environments/environments.json`.

## Things to remember

* The reference feedback log lives in `docs/reference-feedback.md`; keep adding to it.
* Service `packages.lock.json` files are intentionally not committed (they would carry local
  feed hashes). `platform-libraries` lock files are committed and restored in locked mode.
* Local restores of services need the local feed config trick documented in the root README.
* Application Insights is pinned to the 2.x SDK in `Meridian.ServiceDefaults`.
