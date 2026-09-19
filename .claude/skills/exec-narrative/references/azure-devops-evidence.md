# Azure DevOps evidence: commands and traps

All of these are read-only and work without a PAT because the azure-devops CLI extension holds a
credential for the organization. Run them from PowerShell 7, not Git Bash: Git Bash rewrites
leading-slash arguments and `$expand` into Windows paths. `$org = "https://dev.azure.com/coolhome"`.

## Runs

```powershell
az pipelines runs list --org $org --project Meridian --top 20 -o json | ConvertFrom-Json -Depth 16 |
  Select-Object id, @{n='def';e={$_.definition.name}}, result, status, reason, queueTime, finishTime
```

Runs queued at the end of a session finish after it. Check them before trusting any handoff.

## Timeline of one run: stages, jobs, tasks, issues

```powershell
$id = $run.id   # capture first, see the trap below
$tl = az devops invoke --org $org --area build --resource timeline --route-parameters project=Meridian buildId=$id --api-version 7.1-preview -o json | ConvertFrom-Json -Depth 32
$tl.records | Where-Object { $_.type -in 'Stage','Job' } | Sort-Object order | ForEach-Object { "[$($_.type)] $($_.name): $($_.result)" }
$tl.records | Where-Object { $_.type -eq 'Task' -and $_.result -eq 'failed' } | Select-Object name, @{n='log';e={$_.log.id}}, @{n='issues';e={$_.issues.message}}
```

Trap: `buildId=$r.id` inside an argument stringifies the whole run object and the API fails with
a `KeyError` on the object's text. Assign `$id = $r.id` on its own line first.

## Log of one task

```powershell
$log = az devops invoke --org $org --area build --resource logs --route-parameters project=Meridian buildId=$id logId=$logId --api-version 7.1-preview -o json | ConvertFrom-Json -Depth 8
@($log.value) | Where-Object { $_ -match 'error|403|404|BCP|DeploymentFailed' }
```

ARM deployment failures carry the inner errors as JSON on the `ERROR:` line. Strip the prefix,
`ConvertFrom-Json`, and read `.error.details[].message`; nested `ResourceNotFound` messages are
JSON strings inside that.

## Hosted minutes and parallel jobs

```powershell
az devops invoke --org $org --area distributedtask --resource resourceusage --query-parameters parallelismTag=Private poolIsHosted=true includeRunningRequests=true --api-version 7.1-preview -o json
```

`usedMinutes` against `resourceLimit.totalMinutes`; `resourceLimit.totalCount` is the parallel
job count. `poolIsHosted=false` gives the self-hosted grant (no minute limit).

## Variable groups, checks, pools, feeds

```powershell
az pipelines variable-group list --org $org --project Meridian -o json     # names and values, secrets masked
az devops invoke --org $org --area pipelineschecks --resource configurations --route-parameters project=Meridian id=85 --query-parameters '$expand=settings' --api-version 7.1-preview
az pipelines pool list --org $org -o table
```

The feed `meridian` is project-scoped: its URL contains `/Meridian/_packaging/`. A 404 saying the
feed does not exist at `/coolhome/_packaging/` is a scoping bug, not a permission problem.

## GitHub side

```bash
gh run list --workflow=sync-to-azure-repos.yml --limit 3
gh run view <id> --log-failed
```

## Traps that cost time before

* `--api-version 7.1-preview`, never `7.1-preview.1`.
* The automation sandbox refuses `az pipelines run`, permission grants and approval changes, and
  refuses reads bundled in the same command as a refused write. Keep reads in their own command.
* `"$var?x"` in PowerShell reads a variable named `var?`.
* A handoff written while runs were still queued describes hypotheses; the timeline and logs
  describe facts.
