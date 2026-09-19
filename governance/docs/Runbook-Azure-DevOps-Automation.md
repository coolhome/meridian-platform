# Runbook: Azure DevOps automation

All scripts read `repos.manifest.json`. Environment variables override the manifest:
`MERIDIAN_ADO_ORG_URL`, `MERIDIAN_ADO_PROJECT`, `AZDO_PAT`.

| Task | Command |
| --- | --- |
| Bootstrap project, teams, area paths, iterations, feed, wiki, environments, checks, variable groups, service connections, pipeline settings | `pwsh tooling/Initialize-AzureDevOps.ps1` |
| Mirror all folders | `pwsh tooling/Sync-ToAzureRepos.ps1` |
| Mirror some folders | `pwsh tooling/Sync-ToAzureRepos.ps1 -Folders approval-service,worker-jobs` |
| Create or update pipelines and grant permissions | `pwsh tooling/New-AdoPipelines.ps1` |
| Apply branch and repository policies | `pwsh tooling/Set-AdoBranchPolicies.ps1` |
| Everything after bootstrap | `pwsh tooling/Publish-Platform.ps1` |
| Back-port an Azure Repos hotfix | `pwsh tooling/Sync-FromAzureRepos.ps1 -Folder approval-service -Branch hotfix/AB1234` |
| Compile every consumer against a template ref | `pwsh tooling/Test-PipelineTemplates.ps1 -TemplatesRef refs/heads/feature/x` |

## Gotchas collected from the reference and from running this

* REST calls that are not authenticated return an HTML sign-in page with HTTP 200. The helper
  sends `X-TFS-FedAuthRedirect: Suppress` so they fail as 401/302.
* `TF401019` is a job-token problem. "This pipeline needs permission to access a resource" is a
  pipeline-permissions problem. Fix the axis the message names.
* The project build service identity does not exist until a pipeline has run once, so required
  reviewer and feed grants for it are applied on the second pass.
* Organization-level pipeline settings can lock the project-level ones. If a PATCH succeeds but
  the value does not change, check the organization.
* Service connection preview succeeding does not prove the token exchange works. Check identity,
  federated credential, role assignment and network separately.
* Run parallel `az` invocations with distinct `AZURE_CONFIG_DIR` values.
* Paths in triggers are case-sensitive.
