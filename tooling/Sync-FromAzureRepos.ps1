#Requires -Version 7.2
<#
.SYNOPSIS
    Back-ports commits made in an Azure Repo (for example an emergency hotfix branch)
    into the monorepo folder with `git subtree pull --squash`.
.EXAMPLE
    pwsh tooling/Sync-FromAzureRepos.ps1 -Folder approval-service -Branch hotfix/AB1234
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Folder,
    [Parameter(Mandatory)][string]$Branch,
    [string]$ManifestPath,
    [string]$Pat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$repo = Get-MeridianMirroredRepos -Manifest $m -Folders @($Folder) | Select-Object -First 1
if (-not $repo) { throw "Folder '$Folder' is not a mirrored repo in the manifest." }
$authHeader = Get-GitAuthHeader -Pat ($Pat ?? $env:AZDO_PAT)
$url = Get-AdoRepoRemoteUrl -Manifest $m -RepoName $repo.name

Push-Location $m.RootPath
try {
    if (& git status --porcelain) { throw 'Working tree must be clean before a subtree pull.' }
    & git -c "http.extraheader=$authHeader" subtree pull --prefix=$Folder $url $Branch --squash -m "chore($Folder): back-port $Branch from Azure Repos $($repo.name)"
    if ($LASTEXITCODE -ne 0) { throw 'subtree pull failed; resolve conflicts and commit.' }
    Write-MeridianOk "back-ported $($repo.name)/$Branch into $Folder. Open a PR; the next sync pushes the merge back."
}
finally { Pop-Location }
