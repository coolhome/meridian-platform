<#
.SYNOPSIS
  Read-only snapshot of Azure Pipelines state for the executive narrative.
.DESCRIPTION
  Prints hosted parallel-job minute usage, the latest runs, and for each failed run the stage and
  job results plus the issues and error log lines of every failed task. Uses `az devops invoke`,
  so it works in credential-manager mode without a PAT. Run from PowerShell 7.
.EXAMPLE
  pwsh .claude/skills/exec-narrative/scripts/Get-PipelineState.ps1 -Top 12
#>
[CmdletBinding()]
param(
  [string]$Org = 'https://dev.azure.com/coolhome',
  [string]$Project = 'Meridian',
  [int]$Top = 12,
  [int]$ErrorLines = 8
)
$ErrorActionPreference = 'Stop'

function Invoke-Ado {
  param([string]$Area, [string]$Resource, [string[]]$Route, [string[]]$Query)
  $cli = @('devops', 'invoke', '--org', $Org, '--area', $Area, '--resource', $Resource, '--api-version', '7.1-preview', '-o', 'json')
  if ($Route) { $cli += '--route-parameters'; $cli += $Route }
  if ($Query) { $cli += '--query-parameters'; $cli += $Query }
  $raw = & az @cli 2>$null
  if ($LASTEXITCODE -ne 0) { throw "az $($cli -join ' ') exited $LASTEXITCODE" }
  return ($raw -join "`n") | ConvertFrom-Json -Depth 64
}

function Clip([string]$Text, [int]$Max = 300) {
  $t = ($Text -replace "`r?`n", ' ').Trim()
  if ($t.Length -gt $Max) { $t.Substring(0, $Max) + ' ...' } else { $t }
}

"## Hosted parallel jobs (private projects)"
try {
  $usage = Invoke-Ado -Area distributedtask -Resource resourceusage -Query @('parallelismTag=Private', 'poolIsHosted=true', 'includeRunningRequests=true')
  "used minutes: $($usage.usedMinutes) of $($usage.resourceLimit.totalMinutes); parallel jobs: $($usage.resourceLimit.totalCount); running now: $($usage.usedCount)"
} catch { "could not read resource usage: $_" }
""

"## Latest $Top runs"
$runs = az pipelines runs list --org $Org --project $Project --top $Top -o json | ConvertFrom-Json -Depth 16
"| Run | Pipeline | Result | Reason | Queued (UTC) | Minutes |"
"| --- | --- | --- | --- | --- | --- |"
foreach ($r in $runs) {
  $res = if ($r.result) { $r.result } else { $r.status }
  $mins = if ($r.finishTime -and $r.startTime) { [math]::Round(([datetime]$r.finishTime - [datetime]$r.startTime).TotalMinutes, 1) } else { '' }
  $q = ([datetime]$r.queueTime).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
  "| $($r.id) | $($r.definition.name) | $res | $($r.reason) | $q | $mins |"
}
""

"## Failed runs: stages, jobs, failing tasks"
foreach ($r in ($runs | Where-Object { $_.result -eq 'failed' })) {
  $id = $r.id   # capture first: "buildId=$r.id" inside an argument stringifies the whole object
  "### $id $($r.definition.name)"
  $tl = Invoke-Ado -Area build -Resource timeline -Route @("project=$Project", "buildId=$id")
  foreach ($rec in ($tl.records | Where-Object { $_.type -in 'Stage', 'Job' } | Sort-Object order)) {
    $state = if ($rec.result) { $rec.result } else { $rec.state }
    "  [$($rec.type)] $($rec.name): $state"
  }
  foreach ($task in ($tl.records | Where-Object { $_.type -eq 'Task' -and $_.result -eq 'failed' })) {
    "  FAILED TASK: $($task.name)"
    foreach ($issue in (@($task.issues) | Where-Object { $_.type -eq 'error' } | Select-Object -First 3)) {
      "    issue: " + (Clip $issue.message)
    }
    if ($task.log.id) {
      try {
        $log = Invoke-Ado -Area build -Resource logs -Route @("project=$Project", "buildId=$id", "logId=$($task.log.id)")
        # -match is case-insensitive; word boundaries keep GUIDs containing "404c" out of the hits
        $hits = @($log.value) |
          Where-Object { $_ -match 'error|\b(401|403|404)\b|denied|Forbidden|BCP\d+|DeploymentFailed' } |
          Where-Object { $_ -notmatch '\[command\]|"id":\s*"' } |
          Select-Object -First $ErrorLines
        foreach ($l in $hits) { "    log: " + (Clip ($l -replace '^\S+Z\s*', '')) }
      } catch { "    log: could not read log $($task.log.id): $_" }
    }
  }
  ""
}
