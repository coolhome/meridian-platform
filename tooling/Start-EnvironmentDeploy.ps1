#Requires -Version 7.2
<#
.SYNOPSIS
    Queues the governed pipelines that build an environment, in dependency order, and waits for each.
.DESCRIPTION
    Nothing here deploys anything itself. Every step is `az pipelines run` against the same pipelines a
    merge to main triggers, so every check (required template, branch control, approvals, locks) still
    applies. Which environments a pipeline deploys is declared in each consumer's azure-pipelines.yml;
    this script only orders the runs and reports the outcome, and -Environment names the environment
    whose resource groups are verified at the end.

    Order:
      1. platform-infrastructure-cicd      (resource groups, monitoring, Key Vault, data, identities)
      2. containers-base-images            (only with -IncludeShared; shared registry images)
      3. platform-libraries-cicd           (NuGet packages the services restore)
      4. every service-tier cicd pipeline  (the .NET services are fired by their pipeline resource
                                           trigger on platform-libraries; runs that do not appear
                                           within a few minutes, such as app-frontend, are queued here)
      5. observability-cicd                (alerts target the Container Apps, so it goes last)

    Step 4 recognises the runs the libraries Publish stage fired by their triggerInfo, not by reason: the
    Build REST API reports a resource-triggered run with reason 'manual' and requestedBy
    'Microsoft.VisualStudio.Services.TFS', and triggerInfo (pipelineTriggerType PipelineCompletion,
    pipelineId = the producer run id, source = the producer pipeline name) is what identifies it. They are
    queued when the Publish stage ends, well before the libraries run itself finishes, so the window they
    must fall in starts at the libraries run's own queue time.

    The shared stage of platform-infrastructure pauses for the Platform Engineering approval. With
    -ApproveShared, Approve-PendingApprovals.ps1 -Wait runs alongside and records your approval from
    the terminal (needs AZDO_PAT); without it, approve in the portal when the run pauses.
    Hosted parallelism is 1, so runs execute one at a time; a full dev wave is roughly 60 to 90 minutes.
.EXAMPLE
    pwsh tooling/Start-EnvironmentDeploy.ps1 -Environment dev -ApproveShared
.EXAMPLE
    pwsh tooling/Start-EnvironmentDeploy.ps1 -Environment dev -Only platform-libraries-cicd,app-frontend-cicd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'test', 'prod')][string]$Environment,
    [string]$Branch = 'main',
    [switch]$ApproveShared,
    [switch]$IncludeShared,
    [string[]]$Only,             # run just these pipelines (still in the order above)
    [int]$TimeoutMinutes = 90,
    [int]$PollSeconds = 30,
    [string]$ManifestPath,
    [string]$Pat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$null = Connect-MeridianAdo -Manifest $m -Pat $Pat
$prefix = $m.platform.resourcePrefix
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

function Get-CicdPipelineName([string]$Folder) {
    $repo = $m.repos | Where-Object { $_.folder -eq $Folder } | Select-Object -First 1
    return ($repo.pipelines | Where-Object { $_.kind -eq 'cicd' } | Select-Object -First 1).name
}
$infraPipeline = Get-CicdPipelineName 'platform-infrastructure'
$containersPipeline = Get-CicdPipelineName 'containers'
$librariesPipeline = Get-CicdPipelineName 'platform-libraries'
$observabilityPipeline = Get-CicdPipelineName 'observability'
$servicePipelines = @($m.repos | Where-Object { $_.tier -eq 'service' } | ForEach-Object { ($_.pipelines | Where-Object { $_.kind -eq 'cicd' }).name } | Where-Object { $_ })
function Wanted([string]$Name) { return (-not $Only) -or ($Only -contains $Name) }

$results = [System.Collections.Generic.List[object]]::new()
function Get-RunUrl([int]$Id) {
    # Built, not read: az's JSON output drops underscore-prefixed keys such as _links (every other declared Build
    # field is present, as null when unset), and under StrictMode reading the missing property throws.
    return "$($m.azureDevOps.organizationUrl)/$([uri]::EscapeDataString($m.azureDevOps.project))/_build/results?buildId=$Id"
}
function Start-Run([string]$Name) {
    $run = Invoke-AzCli pipelines run --name $Name --branch $Branch
    Write-MeridianOk "queued $Name run $($run.id) ($($run.buildNumber))"
    return $run
}
function Wait-Runs([object[]]$Runs) {
    # Polls every run until it completes; records results. Hosted parallelism is 1, so this is mostly waiting.
    $pending = @{}
    foreach ($r in $Runs) { $pending[[int]$r.id] = $r.definition.name }
    while ($pending.Count -gt 0) {
        if ((Get-Date) -gt $deadline) { throw "timeout after $TimeoutMinutes minutes with $($pending.Count) run(s) still going: $($pending.Values -join ', ')" }
        Start-Sleep -Seconds $PollSeconds
        foreach ($id in @($pending.Keys)) {
            $b = Invoke-AzCli pipelines runs show --id $id
            if ($b.status -ne 'completed') { continue }
            $minutes = if ($b.startTime -and $b.finishTime) { [math]::Round(([datetime]$b.finishTime - [datetime]$b.startTime).TotalMinutes, 1) } else { '' }
            $results.Add([pscustomobject]@{ pipeline = $pending[$id]; run = $id; number = $b.buildNumber; result = $b.result; minutes = $minutes; url = (Get-RunUrl $id) })
            $color = if ($b.result -eq 'succeeded') { 'Green' } else { 'Red' }
            Write-Host "    $($b.result.PadRight(18)) $($pending[$id]) run $id ($minutes min)" -ForegroundColor $color
            $pending.Remove($id)
        }
    }
}
function Get-OptionalProperty([object]$Object, [string]$Name) {
    # StrictMode-safe read of a property that may be absent (a hand-queued run has no triggerInfo; a CI run's has no
    # pipelineTriggerType).
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    return $(if ($p) { $p.Value } else { $null })
}
function Test-ProducerTriggeredRun([object]$Run, [int]$ProducerRunId, [datetime]$NotBefore) {
    # The Build REST API reports a run fired by a pipeline resource trigger with reason 'manual' and requestedBy
    # 'Microsoft.VisualStudio.Services.TFS'; only triggerInfo says which resource fired it:
    #   PipelineCompletion: alias, artifactType Pipeline, source <producer pipeline>, pipelineId <producer run id>, version <its buildNumber>
    #   ContainerImage:     alias, artifactType AzureContainerRepository, tag
    # A CI run's triggerInfo holds ci.sourceBranch, ci.sourceSha and the like, and a hand-queued run has none; neither
    # carries pipelineTriggerType, hence the guarded reads. The producer run id is the key (run ids are unique in the
    # organization, so no producer-name fallback); the queue-time window is a sanity check, since nothing the producer
    # fired can predate the producer's own queue time.
    $info = Get-OptionalProperty $Run 'triggerInfo'
    if ((Get-OptionalProperty $info 'pipelineTriggerType') -ne 'PipelineCompletion') { return $false }
    if ([string](Get-OptionalProperty $info 'pipelineId') -ne [string]$ProducerRunId) { return $false }
    return ([datetime]$Run.queueTime -gt $NotBefore)
}

$approver = $null
if ($ApproveShared) {
    if (-not ($Pat ?? $env:AZDO_PAT)) { throw '-ApproveShared needs AZDO_PAT (Approve-PendingApprovals.ps1 has no credential-manager fallback)' }
    $script = Join-Path $PSScriptRoot 'Approve-PendingApprovals.ps1'
    $approver = Start-Job -ScriptBlock { param($s, $max, $pat) & $s -Wait -MaxMinutes $max -Pat $pat } -ArgumentList $script, $TimeoutMinutes, ($Pat ?? $env:AZDO_PAT)
    Write-MeridianInfo "Approve-PendingApprovals.ps1 -Wait is running alongside (job $($approver.Id))"
}

try {
    # 1. infrastructure
    if (Wanted $infraPipeline) {
        Write-MeridianStep "1. $infraPipeline"
        Wait-Runs @(Start-Run $infraPipeline)
        if (($results | Where-Object { $_.pipeline -eq $infraPipeline }).result -ne 'succeeded') { throw "$infraPipeline did not succeed; stopping before the services" }
    }
    # 2. base images (shared)
    if ($IncludeShared -and (Wanted $containersPipeline)) {
        Write-MeridianStep "2. $containersPipeline"
        Wait-Runs @(Start-Run $containersPipeline)
    }
    # 3. libraries
    $librariesRunId = 0
    $librariesQueued = $null
    if (Wanted $librariesPipeline) {
        Write-MeridianStep "3. $librariesPipeline"
        $librariesRun = Start-Run $librariesPipeline
        Wait-Runs @($librariesRun)
        $librariesRunId = [int]$librariesRun.id
        $librariesQueued = [datetime]$librariesRun.queueTime
        if (($results | Where-Object { $_.pipeline -eq $librariesPipeline }).result -ne 'succeeded') { throw "$librariesPipeline did not succeed; the services cannot restore, stopping" }
    }
    # 4. services: wait for the runs the libraries resource trigger fired (matched by triggerInfo, see
    #    Test-ProducerTriggeredRun: their REST reason is 'manual'), queue whichever did not fire. The window
    #    starts at the libraries run's queue time, not its finish: a stage-completion trigger fires when the
    #    Publish stage ends, which on run 3964 was 24 minutes before the run itself finished, so a window
    #    anchored on the finish would veto every run it fired. The list is ordered by queue time on purpose:
    #    the default order is by finish time, which puts a run that has not finished yet (every run this step
    #    is looking for) after the completed ones and outside --top; 10 leaves room for the container-image
    #    trigger's runs, which can land in front of the libraries-fired one.
    $wantedServices = @($servicePipelines | Where-Object { Wanted $_ })
    if ($wantedServices.Count) {
        Write-MeridianStep "4. services: $($wantedServices -join ', ')"
        $runs = @{}
        if ($librariesQueued) {
            $until = (Get-Date).AddMinutes(4)
            while ((Get-Date) -lt $until -and $runs.Count -lt $wantedServices.Count) {
                Start-Sleep -Seconds 20
                foreach ($name in $wantedServices | Where-Object { -not $runs.ContainsKey($_) }) {
                    $def = Get-AdoPipelineDefinition -Name $name
                    if (-not $def) { continue }
                    $recent = @(Invoke-AzCli pipelines runs list --pipeline-ids $def.id --top 10 --query-order QueueTimeDesc) |
                        Where-Object { Test-ProducerTriggeredRun -Run $_ -ProducerRunId $librariesRunId -NotBefore $librariesQueued } |
                        Select-Object -First 1
                    if ($recent) {
                        $runs[$name] = $recent
                        $ti = $recent.triggerInfo
                        Write-MeridianOk "$name run $($recent.id) fired by the $($ti.pipelineTriggerType) trigger: $librariesPipeline run $(Get-OptionalProperty $ti 'pipelineId') ($(Get-OptionalProperty $ti 'version'))"
                    }
                }
            }
        }
        foreach ($name in $wantedServices | Where-Object { -not $runs.ContainsKey($_) }) { $runs[$name] = Start-Run $name }
        Wait-Runs @($runs.Values)
    }
    # 5. observability
    if (Wanted $observabilityPipeline) {
        Write-MeridianStep "5. $observabilityPipeline"
        Wait-Runs @(Start-Run $observabilityPipeline)
    }
}
finally {
    if ($approver) {
        Stop-Job $approver -ErrorAction SilentlyContinue
        $out = Receive-Job $approver -ErrorAction SilentlyContinue
        if ($out) { Write-MeridianInfo "approver output:`n$($out -join "`n")" }
        Remove-Job $approver -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
$results | Format-Table pipeline, run, number, result, minutes -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.result -ne 'succeeded' })

# The environment's resource groups are the cheapest proof the wave did something.
$groups = @(& az group list --query "[?starts_with(name, 'rg-$prefix-$Environment-')].name" -o tsv --only-show-errors)
Write-MeridianInfo "resource groups for $Environment`: $(if ($groups) { $groups -join ', ' } else { 'none' })"

if ($failed.Count) { Write-Host "$($failed.Count) run(s) did not succeed" -ForegroundColor Red; exit 1 }
Write-Host "wave complete" -ForegroundColor Green
