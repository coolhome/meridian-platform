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

Set `AZDO_PAT` (or pass `-Pat`). Required scopes are listed by the module when the variable
is missing. Override the manifest with `MERIDIAN_ADO_ORG_URL` / `MERIDIAN_ADO_PROJECT`.

## Order of operations for a new organization

```bash
pwsh tooling/Initialize-AzureDevOps.ps1        # skips service connections until IDs are filled in
pwsh tooling/Publish-Platform.ps1              # mirrors, pipelines, policies, wiki
pwsh tooling/Initialize-AzureDevOps.ps1        # second pass: required-template checks now that the templates repo exists
pwsh tooling/New-AdoPipelines.ps1              # second pass after first pipeline run: build-service tag rights
```
