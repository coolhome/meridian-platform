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
| `Set-AdoBranchPolicies.ps1` | Apply branch + repository policy profiles |
| `Publish-Platform.ps1` | Boundary check -> sync -> pipelines -> policies -> wiki |
| `Test-RepoBoundaries.ps1` | ADR 0004 enforcement (also runs in GitHub PR validation) |
| `Sync-GovernanceOverlay.ps1` | Stamp overlay files into every mirrored folder |
| `Get-ChangedFolders.ps1` | Map a git diff to mirrored folders (drives the workflows) |
| `Test-PipelineTemplates.ps1` | Preview-compile every consumer against a templates ref |
| `lib/Meridian.Ado.psm1` | Shared REST/CLI helpers |

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
