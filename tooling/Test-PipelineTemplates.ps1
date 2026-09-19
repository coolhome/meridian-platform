#Requires -Version 7.2
<#
.SYNOPSIS
    Compiles every consumer pipeline against a candidate templates ref using the pipelines
    preview API (no run is queued). Run before tagging a new templates version.
.EXAMPLE
    pwsh tooling/Test-PipelineTemplates.ps1 -TemplatesRef refs/heads/feature/new-scan
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TemplatesRef,
    [string]$ManifestPath,
    [string]$Pat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$null = Connect-MeridianAdo -Manifest $m -Pat $Pat
$failed = 0
foreach ($repo in Get-MeridianMirroredRepos -Manifest $m) {
    if ($repo.name -eq $m.azureDevOps.templatesRepository -or $repo.tier -eq 'governance') { continue }
    foreach ($p in $repo.pipelines) {
        $def = Get-AdoPipelineDefinition -Name $p.name
        if (-not $def) { Write-MeridianWarn "$($p.name) not found"; continue }
        $body = @{ previewRun = $true; resources = @{ repositories = @{ templates = @{ refName = $TemplatesRef } } } }
        try {
            $null = Invoke-AdoRest -Method POST -ProjectScoped -Path "pipelines/$($def.id)/preview" -Body $body
            Write-MeridianOk $p.name
        }
        catch {
            $failed++
            Write-Host "FAIL $($p.name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
if ($failed) { Write-Host "$failed consumer(s) failed to compile against $TemplatesRef" -ForegroundColor Red; exit 1 }
Write-Host "All consumers compile against $TemplatesRef" -ForegroundColor Green
