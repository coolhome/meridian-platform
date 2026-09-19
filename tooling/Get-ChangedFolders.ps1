#Requires -Version 7.2
<#
.SYNOPSIS
    Lists mirrored folders touched between two commits. Used by GitHub workflows to sync
    and build only what changed. Changes to the overlay, manifest or governance policies
    fan out to every mirrored folder.
.OUTPUTS
    JSON array of folder names on stdout. Also writes `folders`, `any`, `governance`
    outputs to $GITHUB_OUTPUT when present.
#>
[CmdletBinding()]
param(
    [string]$Base,
    [string]$Head = 'HEAD',
    [string]$ManifestPath,
    [switch]$All
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$mirrored = @((Get-MeridianMirroredRepos -Manifest $m).folder)
$governanceChanged = $false

if ($All -or -not $Base -or $Base -match '^0+$') {
    $folders = $mirrored
    $governanceChanged = $true
}
else {
    $changed = @(& git -C $m.RootPath diff --name-only "$Base" "$Head")
    if ($LASTEXITCODE -ne 0) { throw 'git diff failed (shallow clone? use fetch-depth: 0).' }
    $set = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($path in $changed) {
        $top = $path.Split('/')[0]
        if ($path -like "$($m.governance.overlay)/*" -or $path -eq 'repos.manifest.json' -or $path -like 'governance/policies/*' -or $path -like 'governance/environments/*') {
            $governanceChanged = $true
            foreach ($f in $mirrored) { $null = $set.Add($f) }
        }
        elseif ($mirrored -contains $top) { $null = $set.Add($top) }
    }
    $folders = @($set | Sort-Object)
}

$json = ConvertTo-Json @($folders) -Compress
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "folders=$json"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "any=$(($folders.Count -gt 0).ToString().ToLower())"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "governance=$($governanceChanged.ToString().ToLower())"
    $dotnet = @($folders | Where-Object { Test-Path (Join-Path $m.RootPath $_ 'global.json') })
    $node = @($folders | Where-Object { Test-Path (Join-Path $m.RootPath $_ 'package.json') })
    $bicep = @($folders | Where-Object { Get-ChildItem (Join-Path $m.RootPath $_) -Recurse -Filter *.bicep -ErrorAction SilentlyContinue | Select-Object -First 1 })
    Add-Content -Path $env:GITHUB_OUTPUT -Value "dotnet=$(ConvertTo-Json @($dotnet) -Compress)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "node=$(ConvertTo-Json @($node) -Compress)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "bicep=$(ConvertTo-Json @($bicep) -Compress)"
}
Write-Output $json
