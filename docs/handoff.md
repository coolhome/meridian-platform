> Superseded by [handoff-2.md](handoff-2.md) (2026-09-19, end of session two). Step 4 (local stack) below is still current.

# Handoff: state of the Meridian rollout (2026-09-19, second session)

Read this first when continuing in a new session. Everything below was verified in the
session that wrote it unless marked *assumed*.

## Where things stand

| Area | State |
| --- | --- |
| Monorepo scaffold | Complete on `main`. Builds, tests, lint, Bicep compile and the boundary check pass. |
| GitHub | `coolhome/meridian-platform` exists (private), `main` pushed. Repository variables `MERIDIAN_ADO_ORG_URL` and `MERIDIAN_ADO_PROJECT` are set. **Secret `AZDO_PAT` is not set**, so the `Sync to Azure Repos` workflow fails until it is. |
| Azure DevOps project | `https://dev.azure.com/coolhome/Meridian` created by `Initialize-AzureDevOps.ps1`: pipeline settings, 4 security groups, 5 teams with area paths, 6 sprints, feed `meridian`, variable groups (`meridian-shared`, `-dev`, `-test`, `-prod`, `meridian-dev-kv` Key Vault-linked), environments `shared` (39), `dev` (40), `test` (41), `prod` (42), `packages` (43) with branch control, approvals, business hours and the prod exclusive lock. |
| Service connections | `sc-meridian-shared` and `sc-meridian-dev` (workload identity federation) exist and their federated credentials are on the identities. `test` and `prod` are skipped until `environments.json` has real values for them. |
| Azure | Deployed directly with `az deployment sub create`: `shared` (registry `acrmrdshared`, Log Analytics, App Insights, per-service identities) and `dev` (Container Apps environment `cae-mrd-dev`, Key Vault `kv-mrd-dev-ch2609`, Cosmos `cosmos-mrd-dev-ch2609`, storage `stmrddevch2609`). Unique suffix is `ch2609`. Nothing runs in the Container Apps environment yet. |
| Azure Repos mirrors | **Not created.** `Sync-ToAzureRepos.ps1 -DryRun` resolves all 11 subtree splits, but the push needs credentials (see below). Consequently: no pipelines, no branch policies, no wiki, and the required-template checks are deferred. |
| Pipeline identity roles | **Not granted.** `id-mrd-shared-pipelines` and `id-mrd-dev-pipelines` exist but have no `Contributor` or `Role Based Access Control Administrator` assignment on the subscription. Pipelines cannot deploy until this is done. |
| Local stack | Not started this session (Azurite via `npx --yes azurite`, four services, SPA on 5173). |

## Authentication model (what works without a PAT)

The `az devops` extension holds a credential in Windows Credential Manager for the coolhome
organization. `tooling/lib/Meridian.Ado.psm1` now runs in *credential-manager mode* when
`AZDO_PAT` is unset: every REST call goes through `az devops invoke` (route table
`InvokeRoutes`), and the whole bootstrap plus pipelines and policies can run that way.
What cannot: `git push` to Azure Repos. Git Credential Manager has no stored credential for
`dev.azure.com`, so a non-interactive session fails; an interactive terminal would open a
browser sign-in. An Entra token from `az account get-access-token` is rejected (`TF400813`,
Microsoft-account-owned organization).

## Exact next steps, in order

Steps 1 and 2 need a human: a browser sign-in or PAT, and a subscription Owner approving
role assignments.

```bash
# 1. Azure Repos mirror. Either run in an interactive terminal (GCM opens a browser), or create a PAT at
#    https://dev.azure.com/coolhome/_usersSettings/tokens with scopes
#    Code (read, write, manage), Build (read, execute, manage), Project and Team (read, write),
#    Environment (read, manage), Service Connections (read, query, manage), Variable Groups (read, create, manage),
#    Graph (read, manage), Identity (read), Wiki (read, write), Packaging (read, write, manage), Work Items (read, write), Security (manage)
export AZDO_PAT=...                       # optional when interactive
pwsh ./tooling/Publish-Platform.ps1       # boundary check, mirror, pipelines, policies, wiki
pwsh ./tooling/Initialize-AzureDevOps.ps1 # second pass: required-template checks now that the templates repo exists
gh secret set AZDO_PAT                    # so the GitHub sync workflow works on the next push

# 2. Roles for the pipeline identities (subscription Owner)
az role assignment create --assignee-object-id 625c9e1a-233c-4246-9d03-153efa34dec4 --assignee-principal-type ServicePrincipal --role Contributor --scope /subscriptions/ac39dedd-f5fd-404c-9013-07575f55a6ec
az role assignment create --assignee-object-id 625c9e1a-233c-4246-9d03-153efa34dec4 --assignee-principal-type ServicePrincipal --role "Role Based Access Control Administrator" --scope /subscriptions/ac39dedd-f5fd-404c-9013-07575f55a6ec
az role assignment create --assignee-object-id c8881049-61ae-4c68-8610-76383d33689d --assignee-principal-type ServicePrincipal --role Contributor --scope /subscriptions/ac39dedd-f5fd-404c-9013-07575f55a6ec
az role assignment create --assignee-object-id c8881049-61ae-4c68-8610-76383d33689d --assignee-principal-type ServicePrincipal --role "Role Based Access Control Administrator" --scope /subscriptions/ac39dedd-f5fd-404c-9013-07575f55a6ec

# 3. First pipeline runs, in this order (one free hosted parallel job, 1800 min/month, about 360 used)
#    platform-infrastructure-cicd, containers-base-images, platform-libraries-cicd, identity-service-cicd,
#    approval-service-cicd, app-backend-cicd, worker-jobs-cicd, app-frontend-cicd, observability-cicd
#    The shared stage waits for an approval from the Platform Engineering team; add yourself to that team first.
pwsh ./tooling/New-AdoPipelines.ps1       # after the first run: build-service tag rights

# 4. Local full stack (unchanged from the first handoff)
npx --yes azurite --silent --location .azurite --skipApiVersionCheck
ASPNETCORE_ENVIRONMENT=Development dotnet identity-service/src/Meridian.Identity.Api/bin/Release/net10.0/Meridian.Identity.Api.dll --urls http://localhost:5100
ASPNETCORE_ENVIRONMENT=Development Messaging__Provider=StorageQueue Messaging__ConnectionString=UseDevelopmentStorage=true dotnet approval-service/src/Meridian.Approval.Api/bin/Release/net10.0/Meridian.Approval.Api.dll --urls http://localhost:5200
ASPNETCORE_ENVIRONMENT=Development dotnet app-backend/src/Meridian.Bff/bin/Release/net10.0/Meridian.Bff.dll --urls http://localhost:5000
ASPNETCORE_ENVIRONMENT=Development dotnet worker-jobs/src/Meridian.Worker/bin/Release/net10.0/Meridian.Worker.dll --urls http://localhost:5300
```

## Identifiers you will need

| Item | Value |
| --- | --- |
| Subscription `Platform` | `ac39dedd-f5fd-404c-9013-07575f55a6ec` |
| Tenant | `c8162553-8d13-43aa-8bd6-a254ccbb9a33` |
| `id-mrd-shared-pipelines` | client `1f7b4ede-0b3a-4b83-9925-09569d17a929`, principal `625c9e1a-233c-4246-9d03-153efa34dec4` |
| `id-mrd-dev-pipelines` | client `b3e4a73a-7b03-4f42-bc50-024c6dbe9fd7`, principal `c8881049-61ae-4c68-8610-76383d33689d` |
| `sc-meridian-shared` | `d1f4b8c4-17af-40e8-839e-ad51ee7ad089` |
| `sc-meridian-dev` | `aca15bc3-e884-4dcc-8277-d7786f317c9e` |
| Project id | `671db7cf-5cc0-49ef-b9c3-bb9d0bc4e7f0` |

## Placeholders still in the tree

* `appsettings.json` `AzureAd` sections (`TenantId`, `ClientId`) in the four services: no Entra app
  registrations exist yet. Local runs use header auth.
* `observability/alerts/params/*.bicepparam` alert e-mail addresses.
* `governance/environments/environments.json` for `test` and `prod` (zero GUIDs, `CHANGE` suffix).
* `.github/CODEOWNERS` maps every path to `@coolhome` because a personal account has no teams.

## Things to remember

* Four project pipeline settings stay `false` after the PATCH (`enforceJobAuthScopeForForks`,
  `enforceNoAccessToSecretsFromForks`, `isCommentRequiredForPullRequest`,
  `requireCommentsForNonTeamMemberAndNonContributors`); they are organization-level toggles.
* The prod approval is one entry (group `Release Managers`), so the service caps the minimum at 1.
  Governance says 2; list individual users in `environments.json` to enforce it.
* `az devops invoke` wants `7.1-preview`, never `7.1-preview.1`; the module normalizes this.
* Running `az identity federated-credential create` from Git Bash mangles the `/eid1/...` subject
  into a Windows path. Use PowerShell or `MSYS_NO_PATHCONV=1`.
* The reference feedback log lives in `docs/reference-feedback.md`; keep adding to it.
* Service `packages.lock.json` files are intentionally not committed. Application Insights is
  pinned to the 2.x SDK in `Meridian.ServiceDefaults`.
