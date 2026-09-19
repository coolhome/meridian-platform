#Requires -Version 7.2
<#
.SYNOPSIS
    Mirrors each manifest folder into its own Azure Repo using `git subtree split`.
.DESCRIPTION
    For every mirrored folder and every sync branch (manifest azureDevOps.syncBranches,
    wildcards expanded against local refs), computes the subtree split commit and pushes it
    to refs/heads/<branch> of the Azure Repo. Split is deterministic, so repeated runs are
    fast-forward. Creates the Azure Repo when missing and sets its default branch.
    The PAT travels in an http.extraheader, never in the remote URL.
.EXAMPLE
    pwsh tooling/Sync-ToAzureRepos.ps1 -Folders approval-service,worker-jobs
.EXAMPLE
    pwsh tooling/Sync-ToAzureRepos.ps1 -Branches main -DryRun
#>
[CmdletBinding()]
param(
    [string[]]$Folders,
    [string[]]$Branches,
    [string]$ManifestPath,
    [string]$Pat,
    [switch]$Force,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$null = Connect-MeridianAdo -Manifest $m -Pat $Pat
$authHeader = Get-GitAuthHeader -Pat ($Pat ?? $env:AZDO_PAT)
$repoRoot = $m.RootPath

Push-Location $repoRoot
try {
    & git rev-parse --is-shallow-repository | Out-Null
    if ((& git rev-parse --is-shallow-repository) -eq 'true') { throw 'Repository is shallow; subtree split needs full history (fetch-depth: 0).' }

    if (-not $Branches) { $Branches = @($m.azureDevOps.syncBranches) }
    $localBranches = @(& git for-each-ref --format='%(refname:short)' refs/heads/)
    $resolved = foreach ($b in $Branches) {
        if ($b.Contains('*')) { $localBranches | Where-Object { $_ -like $b } } else { if ($localBranches -contains $b) { $b } else { Write-MeridianWarn "branch $b not found locally; skipped" } }
    }
    $resolved = @($resolved | Select-Object -Unique)
    if ($resolved.Count -eq 0) { throw 'No branches to sync.' }

    $summary = New-Object System.Collections.Generic.List[object]
    foreach ($repo in Get-MeridianMirroredRepos -Manifest $m -Folders $Folders) {
        Write-MeridianStep "$($repo.folder) -> $($repo.name)"
        $url = Get-AdoRepoRemoteUrl -Manifest $m -RepoName $repo.name
        if (-not $DryRun) { $null = New-AdoRepositoryIfMissing -Name $repo.name }

        foreach ($branch in $resolved) {
            $split = & git subtree split --prefix=$($repo.folder) $branch 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $split) { Write-MeridianWarn "no commits for $($repo.folder) on $branch; skipped"; continue }
            $split = ($split | Select-Object -Last 1).Trim()
            $refspec = "${split}:refs/heads/$branch"
            $pushArgs = @('-c', "http.extraheader=$authHeader", 'push')
            if ($Force) { $pushArgs += '--force' }
            $pushArgs += @($url, $refspec)
            if ($DryRun) {
                Write-MeridianInfo "would push $split -> $($repo.name)/$branch"
            }
            else {
                & git @pushArgs 2>&1 | ForEach-Object { Write-MeridianInfo $_ }
                if ($LASTEXITCODE -ne 0) {
                    throw "push to $($repo.name)/$branch rejected. If GitHub history was rewritten, rerun with -Force (see ADR 0001)."
                }
                Write-MeridianOk "pushed $($split.Substring(0,10)) -> $($repo.name)/$branch"
            }
            $summary.Add([pscustomobject]@{ Folder = $repo.folder; Repo = $repo.name; Branch = $branch; Commit = $split.Substring(0, 10) })
        }
        if (-not $DryRun -and $resolved -contains $m.azureDevOps.defaultBranch) {
            $null = Invoke-AzCli repos update --repository $repo.name --default-branch $m.azureDevOps.defaultBranch -AllowFailure
        }
    }
    Write-Host ''
    $summary | Format-Table -AutoSize | Out-String | Write-Host
}
finally {
    Pop-Location
}
