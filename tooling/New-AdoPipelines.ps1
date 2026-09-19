#Requires -Version 7.2
<#
.SYNOPSIS
    Creates or updates every pipeline in the manifest and authorizes it on the protected
    resources it needs (environments, service connections, variable groups, templates
    repository, agent pool). Grants the project build service tag-push rights.
.NOTES
    Azure Repos (TfsGit) pipelines need no service connection (azp-reference,
    pipeline-definitions). Pipelines are keyed by manifest name; renames show up as
    delete + create, so rename in the manifest deliberately.
#>
[CmdletBinding()]
param(
    [string[]]$Folders,
    [string]$ManifestPath,
    [string]$Pat,
    [switch]$SkipPermissions
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$ctx = Connect-MeridianAdo -Manifest $m -Pat $Pat
$envDefs = Get-MeridianGovernanceFile -Manifest $m -Key environments
$project = Get-AdoProject
if (-not $project) { throw "Project $($ctx.Project) not found. Run Initialize-AzureDevOps.ps1 first." }

$environmentsByTier = @{
    service    = @('dev', 'test', 'prod')
    platform   = @('shared', 'dev', 'test', 'prod')
    library    = @('packages', 'dev', 'test', 'prod')
    governance = @()
}

$created = @{}
foreach ($repo in Get-MeridianMirroredRepos -Manifest $m -Folders $Folders) {
    if (-not $repo.pipelines -or $repo.pipelines.Count -eq 0) { continue }
    Write-MeridianStep "pipelines for $($repo.name)"
    $adoRepo = Get-AdoRepository -Name $repo.name
    if (-not $adoRepo) { Write-MeridianWarn "repo $($repo.name) not found; run Sync-ToAzureRepos.ps1 first"; continue }

    foreach ($p in $repo.pipelines) {
        $existing = Get-AdoPipelineDefinition -Name $p.name
        if ($existing) {
            $null = Invoke-AzCli pipelines update --id $existing.id --yml-path $p.yaml --new-folder-path $repo.pipelineFolder --branch $m.azureDevOps.defaultBranch
            Write-MeridianInfo "updated $($p.name) (id $($existing.id))"
            $created[$p.name] = [int]$existing.id
        }
        else {
            $def = Invoke-AzCli pipelines create --name $p.name --repository $repo.name --repository-type tfsgit --branch $m.azureDevOps.defaultBranch --yml-path $p.yaml --folder-path $repo.pipelineFolder --skip-first-run true
            Write-MeridianOk "created $($p.name) (id $($def.id))"
            $created[$p.name] = [int]$def.id
        }
    }

    if ($SkipPermissions) { continue }

    $ids = @($repo.pipelines | ForEach-Object { $created[$_.name] })
    $deployIds = @($repo.pipelines | Where-Object { $_.kind -in @('cicd', 'scheduled') } | ForEach-Object { $created[$_.name] })

    # templates repository: every pipeline extends it
    $tpl = Get-AdoRepository -Name $m.azureDevOps.templatesRepository
    if ($tpl) {
        Grant-AdoPipelinePermission -ResourceType repository -ResourceId "$($project.id).$($tpl.id)" -PipelineIds $ids
        Write-MeridianOk "authorized on repository $($m.azureDevOps.templatesRepository)"
    }

    # agent pool queue
    $queues = @(Invoke-AzCli pipelines queue list)
    $queue = $queues | Where-Object { $_.name -eq $m.azureDevOps.agentPool } | Select-Object -First 1
    if ($queue) { Grant-AdoPipelinePermission -ResourceType queue -ResourceId $queue.id -PipelineIds $ids; Write-MeridianOk "authorized on pool $($queue.name)" }

    # variable groups
    foreach ($vgName in $m.azureDevOps.variableGroups) {
        $vg = Get-AdoVariableGroup -Name $vgName
        if ($vg) { Grant-AdoPipelinePermission -ResourceType variablegroup -ResourceId $vg.id -PipelineIds $ids }
    }
    Write-MeridianOk 'authorized on variable groups'

    if ($deployIds.Count -gt 0) {
        $envNames = @($environmentsByTier[$repo.tier])
        foreach ($envName in $envNames) {
            $env = Get-AdoEnvironment -Name $envName
            if ($env) { Grant-AdoPipelinePermission -ResourceType environment -ResourceId $env.id -PipelineIds $deployIds }
            $envDef = $envDefs.environments | Where-Object { $_.name -eq $envName } | Select-Object -First 1
            if ($envDef -and $envDef.PSObject.Properties['serviceConnection']) {
                $sc = Get-AdoServiceEndpoint -Name $envDef.serviceConnection
                if ($sc) { Grant-AdoPipelinePermission -ResourceType endpoint -ResourceId $sc.id -PipelineIds $deployIds }
            }
        }
        # everything that builds images needs the shared connection
        $shared = Get-AdoServiceEndpoint -Name $m.azureDevOps.serviceConnections.shared
        if ($shared) { Grant-AdoPipelinePermission -ResourceType endpoint -ResourceId $shared.id -PipelineIds $deployIds }
        Write-MeridianOk "authorized on environments [$($envNames -join ', ')] and their service connections"
    }

    # build service: Contribute (4) + Create tag (32) on the repo so tag-release.yml can push tags
    $buildService = Get-AdoIdentity -Name "$($ctx.Project) Build Service ($($ctx.OrgName))"
    if ($buildService) {
        $token = "repoV2/$($project.id)/$($adoRepo.id)"
        $null = Invoke-AzCli devops security permission update --namespace-id '2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87' --subject $buildService.descriptor --token $token --allow-bit 36 -AllowFailure
        Write-MeridianOk 'build service may contribute and create tags'
    }
    else {
        Write-MeridianWarn 'project build service identity not found yet (it appears after the first pipeline run); rerun to grant tag permissions'
    }
}
Write-Host "`nPipelines: $($created.Count) ensured."
