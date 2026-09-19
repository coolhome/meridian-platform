#Requires -Version 7.2
<# Stamps governance/templates/overlay/** into every mirrored folder. Idempotent. #>
[CmdletBinding()]
param([string]$ManifestPath, [string[]]$Folders)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$overlayRoot = Join-Path $m.RootPath $m.governance.overlay
$files = @(Get-ChildItem -LiteralPath $overlayRoot -Recurse -File -Force)
$changed = 0
foreach ($repo in Get-MeridianMirroredRepos -Manifest $m -Folders $Folders) {
    $folder = Join-Path $m.RootPath $repo.folder
    if (-not (Test-Path $folder)) { Write-MeridianWarn "skip $($repo.folder): folder missing"; continue }
    foreach ($f in $files) {
        $rel = [IO.Path]::GetRelativePath($overlayRoot, $f.FullName)
        $target = Join-Path $folder $rel
        $dir = Split-Path $target -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $src = (Get-Content -LiteralPath $f.FullName -Raw) -replace "`r`n", "`n"
        $cur = if (Test-Path -LiteralPath $target) { (Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n" } else { $null }
        if ($src -ne $cur) {
            [IO.File]::WriteAllText($target, $src, [Text.UTF8Encoding]::new($false))
            $changed++
            Write-MeridianOk "stamped $($repo.folder)/$($rel.Replace('\','/'))"
        }
    }
}
Write-Host "Overlay sync complete. $changed file(s) written."
