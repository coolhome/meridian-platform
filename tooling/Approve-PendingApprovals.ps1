<#
.SYNOPSIS
  Lists and approves pending pipeline approvals (the shared-stage approval) from your own terminal.
.DESCRIPTION
  The automation sandbox refuses approvals, so the platform owner runs this. Without -Wait it approves
  whatever is pending right now. With -Wait it polls until -MaxMinutes elapse, approving each approval
  as it appears, so you can start it before a wave and let the whole wave through.
  There is no filter by environment: the approvals API does not return the resource an approval guards.
  Today only the shared environment carries an approval a run can reach (test and prod are not yet in
  any consumer's environment list). Use -ListOnly to see what is pending before approving anything.
  Auth: $env:AZDO_PAT or -Pat, scope Build (read & execute). Without a PAT the script tries
  `az devops invoke` through the area PipelinesApprovals, which the extension does not expose in every
  organization; if that fails it tells you to set AZDO_PAT.
.EXAMPLE
  pwsh ./tooling/Approve-PendingApprovals.ps1 -ListOnly
.EXAMPLE
  pwsh ./tooling/Approve-PendingApprovals.ps1 -Wait -MaxMinutes 120
#>
[CmdletBinding()]
param(
    [string]$Org = 'https://dev.azure.com/coolhome',
    [string]$Project = 'Meridian',
    [string]$Pat = $env:AZDO_PAT,
    [string]$Comment = 'Approved by tooling/Approve-PendingApprovals.ps1',
    [switch]$ListOnly,
    [switch]$Wait,
    [int]$PollSeconds = 30,
    [int]$MaxMinutes = 90
)
$ErrorActionPreference = 'Stop'
$base = "$($Org.TrimEnd('/'))/$([uri]::EscapeDataString($Project))/_apis/pipelines/approvals"
$headers = if ($Pat) { @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat")) } } else { $null }
"auth: $(if ($headers) { 'PAT' } else { 'az devops credential' })"

function Invoke-Cli {
    param([string]$Method, [string[]]$Query, [string]$BodyJson)
    $cli = @('devops', 'invoke', '--org', $Org, '--area', 'PipelinesApprovals', '--resource', 'approvals', '--http-method', $Method, '--api-version', '7.1-preview', '-o', 'json', '--only-show-errors', '--route-parameters', "project=$Project")
    if ($Query) { $cli += '--query-parameters'; $cli += $Query }
    $file = $null
    try {
        if ($BodyJson) {
            $file = Join-Path ([IO.Path]::GetTempPath()) "approve-$([guid]::NewGuid().ToString('n')).json"
            [IO.File]::WriteAllText($file, $BodyJson, [Text.UTF8Encoding]::new($false))
            $cli += @('--in-file', $file, '--encoding', 'utf-8')
        }
        $out = & az @cli 2>&1
        if ($LASTEXITCODE -ne 0) { throw "az devops invoke failed: $out" }
        $text = ($out | Where-Object { $_ -is [string] }) -join "`n"
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text | ConvertFrom-Json -Depth 32
    }
    finally { if ($file -and (Test-Path $file)) { Remove-Item $file -Force } }
}

function Get-Pending {
    if ($headers) { return @((Invoke-RestMethod -Method GET -Uri "${base}?state=pending&`$expand=steps&api-version=7.1-preview.1" -Headers $headers).value) }
    try { return @((Invoke-Cli -Method GET -Query @('state=pending', '$expand=steps')).value) }
    catch { throw "No PAT, and 'az devops invoke --area PipelinesApprovals' is not available in this organization. Set `$env:AZDO_PAT (scope: Build read & execute) and rerun. Detail: $($_.Exception.Message)" }
}

function Approve-Ids([string[]]$Ids) {
    $body = ConvertTo-Json -InputObject @($Ids | ForEach-Object { @{ approvalId = $_; status = 'approved'; comment = $Comment } }) -Depth 4 -Compress
    if ($headers) { return @((Invoke-RestMethod -Method PATCH -Uri "${base}?api-version=7.1-preview.1" -Headers $headers -ContentType 'application/json' -Body $body).value) }
    return @((Invoke-Cli -Method PATCH -BodyJson $body).value)
}

function Describe($a) {
    $who = (@($a.steps) | ForEach-Object { $_.assignedApprover.displayName }) -join ', '
    $extra = foreach ($p in 'pipeline', 'resource') { if ($a.PSObject.Properties[$p]) { "$p=$($a.$p | ConvertTo-Json -Compress -Depth 4)" } }
    "  $($a.id)  created $($a.createdOn)  needs $($a.minRequiredApprovers)  approvers: $who  $($extra -join ' ')"
}

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$approved = 0
$polls = 0
do {
    $pending = Get-Pending
    if ($pending.Count -gt 0) {
        "$(Get-Date -Format 'HH:mm:ss') pending approvals: $($pending.Count)"
        $pending | ForEach-Object { Describe $_ }
        if (-not $ListOnly) {
            foreach ($r in (Approve-Ids @($pending.id))) {
                "  $($r.id) -> $($r.status)"
                if ($r.status -eq 'approved') { $approved++ }
            }
        }
    }
    elseif (-not $Wait -or $ListOnly) { 'no pending approvals' }
    elseif (($polls++ % 10) -eq 0) { "$(Get-Date -Format 'HH:mm:ss') waiting (poll every $PollSeconds s, until $($deadline.ToString('HH:mm')), Ctrl+C to stop)" }
    if ($Wait -and -not $ListOnly) { Start-Sleep -Seconds $PollSeconds }
} while ($Wait -and -not $ListOnly -and (Get-Date) -lt $deadline)
if ($Wait -and -not $ListOnly) { "done: approved $approved approval(s)" }
