# tooling

GitHub-only automation. Everything reads `repos.manifest.json` and the governance files it
points at. Requires PowerShell 7.2+, Azure CLI with the `azure-devops` extension (installed
on first use) and git 2.30+ with `subtree`.

| Script | Purpose |
| --- | --- |
| `Initialize-AzureDevOps.ps1` | Project, pipeline settings, groups, teams, area paths, iterations, feed, WIF service connections, variable groups, environments + checks |
| `Sync-ToAzureRepos.ps1` | `git subtree split` each folder and push to its Azure Repo (creates repos) |
| `Sync-FromAzureRepos.ps1` | Back-port an Azure Repos branch into a folder (`subtree pull --squash`) |
| `New-AdoPipelines.ps1` | Create/update pipelines, grant pipeline permissions on protected resources, build-service tag rights |
| `Grant-AdoSyncAccess.ps1` | Sync group membership and "bypass policies when pushing" on every mirror (runs before each mirror) |
| `Set-AdoBranchPolicies.ps1` | Apply branch + repository policy profiles |
| `Publish-Platform.ps1` | Boundary check -> sync -> pipelines -> policies -> wiki |
| `Test-RepoBoundaries.ps1` | ADR 0004 enforcement (also runs in GitHub PR validation) |
| `Sync-GovernanceOverlay.ps1` | Stamp overlay files into every mirrored folder |
| `Get-ChangedFolders.ps1` | Map a git diff to mirrored folders (drives the workflows) |
| `Test-PipelineTemplates.ps1` | Preview-compile every consumer against a templates ref |
| `Grant-FeedRole.ps1` | Inspect (`-ReadOnly`) or re-apply the Artifacts feed role for the build service outside the bootstrap |
| `Approve-PendingApprovals.ps1` | Approve pending pipeline approvals from a terminal (`-ListOnly`, `-Wait`) |
| `Remove-AzureEnvironment.ps1` | Tear down one environment's Azure resources (`-WhatIf`, `-Force`); keeps the Key Vault and the pipeline identity; never `shared` |
| `Start-EnvironmentDeploy.ps1` | Queue the governed pipelines in dependency order and wait (`-ApproveShared`, `-IncludeShared`, `-Only`) |
| `lib/Meridian.Ado.psm1` | Shared REST/CLI helpers |

## What this automation does not do

One step in the provisioning path is a human's on purpose: **the `shared` environment
approval.** `Approve-PendingApprovals.ps1` lets an operator clear it without the portal, but the
gate itself is the point of the platform. It needs `AZDO_PAT` (Build read and execute) outright —
the `PipelinesApprovals` area is not exposed to `az devops invoke`, so there is no
credential-manager fallback for approvals.

The feed role grant used to be listed here as impossible. It was not: the bootstrap's PATCH body
was double-wrapped (`ConvertTo-Json -InputObject @(...) -AsArray` produces `[[...]]`) and the
service accepts that as nothing to do. `Initialize-AzureDevOps.ps1` now grants the role and reads
it back; `Grant-FeedRole.ps1` remains as the standalone form and as a diagnostic ladder for
another organization. Context 2 addendum 3 in
[`docs/reference-feedback.md`](../docs/reference-feedback.md) has the full account.

**Serialization rule for every script here:** a request body that is an array is built with
`ConvertTo-Json -InputObject @(...)` and never with `-AsArray` on top; print the string you send,
not the object, when a write returns 200 with an empty result.

## Teardown and redeploy

```bash
pwsh tooling/Remove-AzureEnvironment.ps1 -Environment dev -WhatIf     # inventory + plan, no changes
pwsh tooling/Remove-AzureEnvironment.ps1 -Environment dev -Force      # delete (no prompt)
pwsh tooling/Start-EnvironmentDeploy.ps1 -Environment dev -ApproveShared
```

`Remove-AzureEnvironment.ps1` deletes `rg-<prefix>-<env>-apps` and `-data`, then empties
`-platform` except the Key Vault (purge protection reserves the name for 90 days; a redeploy
updates the vault in place, which is why it is not deleted) and `id-<prefix>-<env>-pipelines`
(the service connection federates to it). The Log Analytics workspace is deleted with `--force`
so no soft-deleted copy is recovered by the next run. Role assignments the deleted service
identities held on the vault and on the shared registry are removed, and the environment's
subscription-scope policy assignments are deleted unless `-KeepPolicyAssignments`. `shared` is
refused.

`Start-EnvironmentDeploy.ps1` is `az pipelines run` in dependency order: infrastructure,
(base images with `-IncludeShared`), libraries, the service pipelines (the .NET ones fire from
their pipeline resource trigger on libraries; whatever has not fired within four minutes is
queued), then observability. With `-ApproveShared` it runs `Approve-PendingApprovals.ps1 -Wait`
alongside. Nothing bypasses a check: the environments a pipeline deploys are declared in that
consumer's `azure-pipelines.yml`.

## Authentication

Two modes, chosen by whether `AZDO_PAT` (or `-Pat`) is set:

| Mode | REST calls | `az devops` / `az repos` / `az pipelines` | git push/pull to Azure Repos |
| --- | --- | --- | --- |
| PAT (`AZDO_PAT` set) | direct `Invoke-RestMethod` with basic auth | PAT via `AZURE_DEVOPS_EXT_PAT` | PAT in `http.extraheader` |
| Credential-manager (no PAT) | `az devops invoke` with the credential stored by `az devops login` (route table `InvokeRoutes` in the module) | stored credential | Git Credential Manager (browser sign-in the first time) |

Use the PAT mode in CI (the GitHub sync workflow). The credential-manager mode is for an operator
workstation where `az devops login` has already been run; an Entra token from `az account
get-access-token` is not accepted by Microsoft-account-owned organizations (`TF400813`), which
is why the module never tries it. Required PAT scopes are listed by the module when neither
credential works. Override the manifest with `MERIDIAN_ADO_ORG_URL` / `MERIDIAN_ADO_PROJECT`.

## Order of operations for a new organization

```bash
pwsh tooling/Initialize-AzureDevOps.ps1        # skips service connections until IDs are filled in
pwsh tooling/Publish-Platform.ps1              # mirrors, pipelines, policies, wiki
pwsh tooling/Initialize-AzureDevOps.ps1        # second pass: required-template checks now that the templates repo exists
pwsh tooling/New-AdoPipelines.ps1              # second pass after first pipeline run: build-service tag rights
```
