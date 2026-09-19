#Requires -Version 7.2
<#
.SYNOPSIS
    Everything after bootstrap, in order: boundary check -> mirror -> pipelines -> policies -> wiki.
#>
[CmdletBinding()]
param(
    [string[]]$Folders,
    [string]$ManifestPath,
    [string]$Pat,
    [switch]$SkipBoundaryCheck,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$null = Connect-MeridianAdo -Manifest $m -Pat $Pat
$common = @{}
if ($ManifestPath) { $common.ManifestPath = $ManifestPath }
if ($Folders) { $common.Folders = $Folders }

if (-not $SkipBoundaryCheck) {
    & (Join-Path $PSScriptRoot 'Test-RepoBoundaries.ps1') -ManifestPath $ManifestPath
    if ($LASTEXITCODE -ne 0) { throw 'Boundary check failed; nothing published.' }
}
& (Join-Path $PSScriptRoot 'Sync-ToAzureRepos.ps1') @common -Pat $Pat -Force:$Force
& (Join-Path $PSScriptRoot 'New-AdoPipelines.ps1') @common -Pat $Pat
& (Join-Path $PSScriptRoot 'Set-AdoBranchPolicies.ps1') @common -Pat $Pat

Write-MeridianStep 'wiki'
$wiki = $m.azureDevOps.wiki
$existing = @(Invoke-AzCli devops wiki list) | Where-Object { $_.name -eq $wiki.name } | Select-Object -First 1
if ($existing) { Write-MeridianInfo "wiki $($wiki.name) exists" }
elseif (Get-AdoRepository -Name $wiki.repository) {
    $null = Invoke-AzCli devops wiki create --name $wiki.name --type codewiki --repository $wiki.repository --mapped-path $wiki.mappedPath --version $m.azureDevOps.defaultBranch
    Write-MeridianOk "published code wiki $($wiki.name) from $($wiki.repository)$($wiki.mappedPath)"
}
Write-Host "`nPlatform published." -ForegroundColor Green
