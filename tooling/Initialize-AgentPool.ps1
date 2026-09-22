#Requires -Version 7.2
<#
.SYNOPSIS
    Creates and exercises the org-level self-hosted agent pool that the shared Container Apps
    jobs (caj-<prefix>-shared-agent, event-driven; caj-<prefix>-shared-agent-placeholder, manual)
    register into. Read tooling/README.md and this header before running anything but -Status.
.DESCRIPTION
    coolhome is a Microsoft-account-owned Azure DevOps organization. Managed DevOps Pools needs
    the organization connected to Microsoft Entra ID, which coolhome is not (an Entra token from
    `az account get-access-token` was already rejected with TF400813 -- see docs/handoff.md,
    session two, and docs/executive/2026-09-22-self-hosted-capacity-assessment.md). The same gap
    forecloses the Entra-identity registration methods for a plain self-hosted agent, which
    leaves a personal access token as the only workable way for both the KEDA azure-pipelines
    scale rule and the agent container itself to authenticate. This is a deliberate, ADR-recorded
    exception to ADR 0006 ("workload identity everywhere"), not an oversight.

    This script only talks to Azure DevOps (agent pool, queue, pipeline permissions) and to the
    Container Apps job (start, poll executions). It never reads or writes the PAT: that secret
    goes from the owner's terminal straight into Key Vault, and the job reads it from there
    (platform-dev's Bicep wires the secretRef). Nothing here needs Key Vault access.

    Owner steps, in order, once platform-infrastructure has deployed the shared Container Apps
    environment and the two jobs (ops runs the pipeline; a human does the three steps that need
    a human):
      1. Azure DevOps > user settings > Personal access tokens > New Token, scope
         "Agent Pools (Read & manage)" only, organization coolhome.
      2. az keyvault secret set --vault-name kv-<prefix>-shared-<uniqueSuffix> --name azdo-agent-pat --value <pat>
         (today's name: kv-mrd-shared-ch2609, per governance/environments/environments.json's
         shared.azure.uniqueSuffix; confirm with -Status or `az keyvault list -g rg-<prefix>-shared-platform`.)
      3. Flip agentPoolEnabled to true in platform-infrastructure/bicep/params/shared.bicepparam
         (platform-dev owns the parameter and the module that reads it).
      4. Run platform-infrastructure-cicd (ops: Start-EnvironmentDeploy.ps1, or queue it directly)
         so the shared stage deploys the Container Apps environment, the two jobs and the secretRef.
      5. pwsh tooling/Initialize-AgentPool.ps1 -RegisterPlaceholder
         (needs -EnsurePool to have run first; combine as -EnsurePool -RegisterPlaceholder.)

    -Status is the default action when no switch is given, because it is read-only: pool, queue,
    agent list (name/status/enabled), and the primary job's last five executions. Safe to run any
    time, including before the pool or the job exist -- it reports that cleanly instead of
    throwing, and a bare invocation never performs an org write.

    -EnsurePool creates the org-level agent pool if it is missing -- an org write, so it must be
    asked for explicitly, never the default. Creating a pool with autoProvision=true also
    provisions this project's queue against it; the pool id and the queue id are both printed,
    because New-AdoPipelines.ps1 (or a future version of it, once consumers repoint from the
    manifest's azureDevOps.agentPool) or a manual Grant-AdoPipelinePermission call needs the
    queue id.

    -AuthorizeAllPipelines grants every pipeline in the project use of that queue in one call
    (allPipelines.authorized = true) instead of the per-pipeline id list New-AdoPipelines.ps1
    uses for the Microsoft-hosted queue. It is a permission grant like Grant-FeedRole.ps1 and
    Approve-PendingApprovals.ps1, so it is its own switch: the auto-mode permission classifier
    may refuse it from an agent session, and CLAUDE.md reserves permission grants for the owner
    or ops running it directly.

    -RegisterPlaceholder starts the manual placeholder job once, waits for its execution to
    finish, then waits for at least one agent (offline is fine; none is not) to show up in the
    pool. Azure DevOps refuses to queue a pipeline against a pool with zero agents ever
    registered, even an event-driven one that will scale from zero, so the placeholder run is
    what makes the pool usable at all.

    Manifest: azureDevOps.agentPool ("Azure Pipelines" today) is read by New-AdoPipelines.ps1 to
    authorize every pipeline on the Microsoft-hosted queue; it is not touched here on purpose,
    because every consumer's pool: block still names the hosted VM image
    (pipeline-templates/variables/common.yml, Meridian.VmImage) until pipelines-dev repoints them
    -- a template-tag change with every consumer re-pinned together, not part of this change. The
    pool name this script manages comes from azureDevOps.selfHostedPool if the manifest has it,
    falling back to 'meridian-agents' otherwise; see the schema and the orchestrator's manifest
    decision.
.EXAMPLE
    pwsh tooling/Initialize-AgentPool.ps1
    Same as -Status: the default action when no switch is given, because it never writes.
.EXAMPLE
    pwsh tooling/Initialize-AgentPool.ps1 -Status
.EXAMPLE
    pwsh tooling/Initialize-AgentPool.ps1 -EnsurePool
.EXAMPLE
    pwsh tooling/Initialize-AgentPool.ps1 -AuthorizeAllPipelines
.EXAMPLE
    pwsh tooling/Initialize-AgentPool.ps1 -RegisterPlaceholder
#>
[CmdletBinding()]
param(
    [switch]$EnsurePool,
    [switch]$AuthorizeAllPipelines,
    [switch]$RegisterPlaceholder,
    [switch]$Status,
    [string]$PoolName,
    [string]$ResourceGroup,
    [string]$JobName,
    [string]$PlaceholderJobName,
    [int]$TimeoutMinutes = 15,
    [int]$PollSeconds = 15,
    [string]$ManifestPath,
    [string]$Pat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$null = Connect-MeridianAdo -Manifest $m -Pat $Pat
$prefix = $m.platform.resourcePrefix

# The Container Apps job lives in the shared environment's subscription, which need not match the
# organization/project's own default context; every `az containerapp` call below is pinned to it,
# the same way Remove-AzureEnvironment.ps1 and Start-EnvironmentDeploy.ps1 pin to an environment's
# subscription instead of relying on `az account set`.
$envDefs = Get-MeridianGovernanceFile -Manifest $m -Key environments
$sharedEnvDef = $envDefs.environments | Where-Object { $_.name -eq 'shared' } | Select-Object -First 1
if (-not $sharedEnvDef -or -not $sharedEnvDef.PSObject.Properties['azure']) { throw "environment 'shared' has no azure block in environments.json" }
$sharedSubscriptionId = $sharedEnvDef.azure.subscriptionId

if (-not $PoolName) {
    $PoolName = if ($m.azureDevOps.PSObject.Properties['selfHostedPool'] -and $m.azureDevOps.selfHostedPool) { $m.azureDevOps.selfHostedPool } else { 'meridian-agents' }
}
if (-not $ResourceGroup) { $ResourceGroup = "rg-$prefix-shared-platform" }
if (-not $JobName) { $JobName = "caj-$prefix-shared-agent" }
if (-not $PlaceholderJobName) { $PlaceholderJobName = "caj-$prefix-shared-agent-placeholder" }

# -Status is the only action that never writes, so a bare invocation defaults to it -- not -EnsurePool,
# which is an org write and must be asked for explicitly.
if (-not ($EnsurePool -or $AuthorizeAllPipelines -or $RegisterPlaceholder -or $Status)) { $Status = $true }

function Get-OptionalProperty([object]$Object, [string]$Name) {
    # StrictMode-safe read of a property that may be absent (a fresh pool has no agents yet; a
    # job that has never run has no executions).
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    return $(if ($p) { $p.Value } else { $null })
}

function Get-AgentPool([string]$Name) {
    $res = Invoke-AdoRest -Path "distributedtask/pools?poolName=$([uri]::EscapeDataString($Name))" -ApiVersion '7.1'
    return @($res.value) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Get-AdoQueueByPoolName([string]$Name) {
    # Queues - List accepts queueName (and actionFilter), not poolName. A queue auto-provisioned for
    # a pool takes the pool's own name, so querying queueName with the pool's name finds it; the
    # client-side filter stays as a safety net against a broader or partial-match response.
    $res = Invoke-AdoRest -ProjectScoped -Path "distributedtask/queues?queueName=$([uri]::EscapeDataString($Name))" -ApiVersion '7.1'
    return @($res.value) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Get-AdoPoolAgents([int]$PoolId) {
    $res = Invoke-AdoRest -Path "distributedtask/pools/$PoolId/agents" -ApiVersion '7.1'
    return @($res.value)
}

function Invoke-EnsurePool {
    Write-MeridianStep "agent pool '$PoolName'"
    $pool = Get-AgentPool -Name $PoolName
    if ($pool) {
        Write-MeridianInfo "pool exists (id $($pool.id))"
    }
    else {
        $body = @{ name = $PoolName; autoProvision = $true }
        $json = ConvertTo-Json -InputObject $body -Compress
        Write-Host "    POST distributedtask/pools body: $json"
        $pool = Invoke-AdoRest -Method POST -Path 'distributedtask/pools' -Body $body -ApiVersion '7.1'
        Write-MeridianOk "created pool '$PoolName' (id $($pool.id))"
    }
    $queue = Get-AdoQueueByPoolName -Name $PoolName
    if (-not $queue) {
        # autoProvision=true provisions this project's queue as part of pool creation; give it one
        # retry in case the read-back races the provisioning.
        Start-Sleep -Seconds 5
        $queue = Get-AdoQueueByPoolName -Name $PoolName
    }
    if ($queue) { Write-MeridianOk "project queue id $($queue.id)" }
    else { Write-MeridianWarn "no project queue found yet for pool '$PoolName' in project $($m.azureDevOps.project); rerun -EnsurePool or -Status shortly" }
    return [pscustomobject]@{ Pool = $pool; Queue = $queue }
}

function Invoke-AuthorizeAllPipelines {
    Write-MeridianStep "authorize every pipeline on the queue for pool '$PoolName'"
    $queue = Get-AdoQueueByPoolName -Name $PoolName
    if (-not $queue) { throw "no queue found for pool '$PoolName'; run -EnsurePool first" }
    $body = @{ allPipelines = @{ authorized = $true } }
    $json = ConvertTo-Json -InputObject $body -Compress
    Write-Host "    PATCH pipelines/pipelinepermissions/queue/$($queue.id) body: $json"
    $response = Invoke-AdoRest -Method PATCH -ProjectScoped -Path "pipelines/pipelinepermissions/queue/$($queue.id)" -Body $body -ApiVersion '7.1-preview.1'
    Write-MeridianInfo "PATCH returned: $(($response | ConvertTo-Json -Depth 6 -Compress) ?? '(empty)')"
    $after = Invoke-AdoRest -ProjectScoped -Path "pipelines/pipelinepermissions/queue/$($queue.id)" -ApiVersion '7.1-preview.1'
    $allPipelines = Get-OptionalProperty $after 'allPipelines'
    $authorized = Get-OptionalProperty $allPipelines 'authorized'
    if ($authorized -eq $true) { Write-MeridianOk "all pipelines authorized on queue $($queue.id)" }
    else { Write-MeridianWarn "read-back does not show allPipelines.authorized = true: $($after | ConvertTo-Json -Depth 6 -Compress)" }
}

function Invoke-RegisterPlaceholder {
    Write-MeridianStep "start placeholder job '$PlaceholderJobName' in $ResourceGroup"
    $null = & az containerapp job start --name $PlaceholderJobName --resource-group $ResourceGroup --subscription $sharedSubscriptionId --only-show-errors -o none 2>&1
    if ($LASTEXITCODE -ne 0) { throw "az containerapp job start failed (exit $LASTEXITCODE) for '$PlaceholderJobName' in $ResourceGroup; has platform-infrastructure deployed it yet (agentPoolEnabled)?" }
    Write-MeridianOk 'placeholder job started'

    Write-MeridianStep 'wait for the placeholder execution to finish'
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $execution = $null
    do {
        Start-Sleep -Seconds $PollSeconds
        $executions = @(Invoke-AzCli containerapp job execution list --name $PlaceholderJobName --resource-group $ResourceGroup --subscription $sharedSubscriptionId -AllowFailure)
        $execution = $executions | Sort-Object { [datetime](Get-OptionalProperty $_.properties 'startTime') } -Descending | Select-Object -First 1
        $st = if ($execution) { Get-OptionalProperty $execution.properties 'status' } else { $null }
        if ($execution) { Write-MeridianInfo "execution $($execution.name): $st" }
    } while ((-not $execution -or $st -in @('Running', 'Processing', $null)) -and (Get-Date) -lt $deadline)
    if (-not $execution) { throw "no execution appeared for '$PlaceholderJobName' within $TimeoutMinutes minutes" }
    if ($st -ne 'Succeeded') { Write-MeridianWarn "placeholder execution ended '$st'; the agent may still have registered before failing -- checking the pool anyway" }
    else { Write-MeridianOk "placeholder execution succeeded ($($execution.name))" }

    Write-MeridianStep "wait for an agent to register in pool '$PoolName'"
    $pool = Get-AgentPool -Name $PoolName
    if (-not $pool) { throw "pool '$PoolName' does not exist; run -EnsurePool first" }
    $agents = @()
    $deadline2 = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        Start-Sleep -Seconds $PollSeconds
        $agents = @(Get-AdoPoolAgents -PoolId $pool.id)
    } while ($agents.Count -eq 0 -and (Get-Date) -lt $deadline2)
    if ($agents.Count -eq 0) { Write-MeridianWarn "no agent appeared in pool '$PoolName' within $TimeoutMinutes minutes (offline is fine; none is not -- pipelines cannot queue against an empty pool)" }
    else { foreach ($a in $agents) { Write-MeridianOk "agent $($a.name): status=$($a.status) enabled=$($a.enabled)" } }
}

function Invoke-Status {
    Write-MeridianStep "status: pool '$PoolName'"
    $pool = Get-AgentPool -Name $PoolName
    if (-not $pool) {
        Write-MeridianInfo "pool '$PoolName' does not exist yet. Run -EnsurePool to create it (ops, after reviewing this script)."
    }
    else {
        Write-MeridianOk "pool id $($pool.id)  isHosted=$(Get-OptionalProperty $pool 'isHosted')  autoProvision=$(Get-OptionalProperty $pool 'autoProvision')"
        $queue = Get-AdoQueueByPoolName -Name $PoolName
        if ($queue) { Write-MeridianOk "project queue id $($queue.id)" } else { Write-MeridianWarn "no project queue for pool '$PoolName' in project $($m.azureDevOps.project)" }
        $agents = @(Get-AdoPoolAgents -PoolId $pool.id)
        if ($agents.Count -eq 0) { Write-MeridianInfo 'no agents registered (run -RegisterPlaceholder once the job is deployed)' }
        else { foreach ($a in $agents) { Write-MeridianInfo "  agent $($a.name)  status=$($a.status)  enabled=$($a.enabled)" } }
    }

    Write-MeridianStep "status: job '$JobName' in $ResourceGroup"
    $job = Invoke-AzCli containerapp job show --name $JobName --resource-group $ResourceGroup --subscription $sharedSubscriptionId -AllowFailure
    if (-not $job) {
        Write-MeridianInfo "job '$JobName' does not exist yet in $ResourceGroup (platform-infrastructure deploys it once agentPoolEnabled is set)"
        return
    }
    Write-MeridianOk "job exists, provisioningState=$(Get-OptionalProperty $job.properties 'provisioningState')"
    $executions = @(Invoke-AzCli containerapp job execution list --name $JobName --resource-group $ResourceGroup --subscription $sharedSubscriptionId -AllowFailure)
    $recent = $executions | Sort-Object { [datetime](Get-OptionalProperty $_.properties 'startTime') } -Descending | Select-Object -First 5
    if ($recent.Count -eq 0) { Write-MeridianInfo 'no executions yet' }
    else { foreach ($e in $recent) { Write-MeridianInfo "  $($e.name)  status=$(Get-OptionalProperty $e.properties 'status')  start=$(Get-OptionalProperty $e.properties 'startTime')  end=$(Get-OptionalProperty $e.properties 'endTime')" } }
}

if ($EnsurePool) { $null = Invoke-EnsurePool }
if ($AuthorizeAllPipelines) { Invoke-AuthorizeAllPipelines }
if ($RegisterPlaceholder) { Invoke-RegisterPlaceholder }
if ($Status) { Invoke-Status }
