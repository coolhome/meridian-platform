#Requires -Version 7.2
<#
.SYNOPSIS
    Makes sure the identity that pushes mirrors can do so once branch policies exist.
.DESCRIPTION
    For every security group in governance/teams/teams.json with bypassPoliciesWhenPushing = true:
    adds its listed members and grants "Bypass policies when pushing" (Git Repositories namespace,
    bit 128) on every mirrored repository that already exists. Repositories that do not exist yet
    are created policy-free by Sync-ToAzureRepos.ps1 and covered by Set-AdoBranchPolicies.ps1.
    Runs before the mirror step of the GitHub sync workflow; idempotent.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$Pat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$ctx = Connect-MeridianAdo -Manifest $m -Pat $Pat
$teams = Get-MeridianGovernanceFile -Manifest $m -Key teams
$project = Get-AdoProject
if (-not $project) { throw "Project $($ctx.Project) not found. Run Initialize-AzureDevOps.ps1 first." }
$gitNamespace = '2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87'

$groups = @((Invoke-AzCli devops security group list --project $ctx.Project).graphGroups)
foreach ($g in $teams.securityGroups | Where-Object { $_.PSObject.Properties['bypassPoliciesWhenPushing'] -and $_.bypassPoliciesWhenPushing }) {
    Write-MeridianStep "sync access for group $($g.name)"
    $graph = $groups | Where-Object { $_.displayName -eq $g.name } | Select-Object -First 1
    if (-not $graph) { Write-MeridianWarn "group $($g.name) not found; run Initialize-AzureDevOps.ps1"; continue }

    if ($g.PSObject.Properties['members'] -and $g.members) {
        $current = Get-AdoGroupMemberNames -Descriptor $graph.descriptor
        foreach ($member in $g.members) {
            if ($current -contains $member) { Write-MeridianInfo "$member is a member"; continue }
            $null = Invoke-AzCli devops security group membership add --group-id $graph.descriptor --member-id $member
            Write-MeridianOk "added $member"
        }
    }

    # the graph descriptor (vssgp.*) is the subject the permission commands expect; IMS identities may carry none
    foreach ($repo in Get-MeridianMirroredRepos -Manifest $m) {
        $adoRepo = Get-AdoRepository -Name $repo.name
        if (-not $adoRepo) { Write-MeridianInfo "$($repo.name) not mirrored yet; skipped"; continue }
        $null = Invoke-AzCli devops security permission update --namespace-id $gitNamespace --subject $graph.descriptor --token "repoV2/$($project.id)/$($adoRepo.id)" --allow-bit 128
        Write-MeridianOk "bypass policies when pushing on $($repo.name)"
    }
}
Write-Host "`nSync access ensured."
