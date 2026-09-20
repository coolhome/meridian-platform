#Requires -Version 7.2
<#
.SYNOPSIS
    Enforces ADR 0004: every mirrored folder must be a self-contained repository.
.DESCRIPTION
    Fails (exit 1) on:
      1. relative paths that escape their folder
      2. missing required files per tier
      3. governance overlay drift
      4. top-level folders not in the manifest
      5. manifest pipeline paths that do not exist
      6. consumer pipelines that do not extend the templates repo at the manifest templatesRef
    Emits GitHub Actions annotations when running in Actions.
#>
[CmdletBinding()]
param([string]$ManifestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$root = $m.RootPath
$errors = New-Object System.Collections.Generic.List[string]
$inActions = [bool]$env:GITHUB_ACTIONS

function Add-Violation([string]$File, [string]$Message) {
    $rel = if ($File) { [IO.Path]::GetRelativePath($root, $File).Replace('\', '/') } else { '' }
    $errors.Add("$rel : $Message")
    if ($inActions -and $rel) { Write-Host "::error file=$rel::$Message" } else { Write-Host "ERROR $rel : $Message" -ForegroundColor Red }
}

$textExt = @('.cs', '.csproj', '.props', '.targets', '.sln', '.slnx', '.json', '.yml', '.yaml', '.bicep', '.bicepparam', '.ts', '.tsx', '.js', '.mjs', '.cjs', '.sh', '.ps1', '.psm1', '.config', '.xml', '.html', '.css', '.md', '.txt', '.kql', '.toml', '.env', '.example')
$skipDirs = @('node_modules', 'bin', 'obj', 'dist', '.git', '.vite', 'TestResults', 'coverage')

$requiredByTier = @{
    governance = @('README.md', 'azure-pipelines.yml')
    platform   = @('README.md', 'azure-pipelines.yml')
    library    = @('README.md', 'azure-pipelines.yml', 'global.json', 'Directory.Build.props', 'nuget.config', 'GitVersion.yml')
    service    = @('README.md', 'azure-pipelines.yml', 'pipelines/pr-validation.yml', 'GitVersion.yml')
}
$dotnetExtra = @('global.json', 'Directory.Build.props', 'nuget.config', 'Dockerfile', '.dockerignore', 'infra/main.bicep')
$nodeExtra = @('package.json', 'package-lock.json', 'infra/main.bicep')

$mirrored = Get-MeridianMirroredRepos -Manifest $m
$overlayRoot = Join-Path $root $m.governance.overlay
$overlayFiles = @(Get-ChildItem -LiteralPath $overlayRoot -Recurse -File -Force)

# 4. top-level folders must be declared
$allowedTop = @('.github', '.claude', 'docs') + @($m.repos.folder)
foreach ($d in Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { $_.Name -ne '.git' }) {
    if ($allowedTop -contains $d.Name) { continue }
    # ADR 0004 binds folders that become Azure Repos. A git-ignored directory is never committed and
    # never mirrored, so it cannot break the one-folder-one-repo boundary: local scratch and agent
    # runtime directories are not violations. Anything tracked still has to be declared.
    $null = & git -C $root check-ignore --quiet -- "$($d.Name)/" 2>$null
    if ($LASTEXITCODE -eq 0) { continue }
    Add-Violation $d.FullName "top-level folder '$($d.Name)' is not declared in repos.manifest.json"
}

foreach ($repo in $mirrored) {
    $folder = Join-Path $root $repo.folder
    if (-not (Test-Path -LiteralPath $folder)) { Add-Violation $folder "manifest folder '$($repo.folder)' does not exist"; continue }

    # 2. required files
    $required = @($requiredByTier[$repo.tier])
    $isDotnet = Test-Path (Join-Path $folder 'src') -PathType Container
    $isNode = Test-Path (Join-Path $folder 'package.json')
    if ($repo.tier -eq 'service' -and $isNode) { $required += $nodeExtra }
    elseif ($repo.tier -eq 'service' -and $isDotnet) { $required += $dotnetExtra }
    foreach ($f in $required) {
        if (-not (Test-Path (Join-Path $folder $f))) { Add-Violation $folder "missing required file '$f' for tier $($repo.tier)" }
    }

    # 3. overlay drift
    foreach ($of in $overlayFiles) {
        $relPath = [IO.Path]::GetRelativePath($overlayRoot, $of.FullName)
        $target = Join-Path $folder $relPath
        if (-not (Test-Path -LiteralPath $target)) { Add-Violation $folder "overlay file '$relPath' missing (run tooling/Sync-GovernanceOverlay.ps1)"; continue }
        $a = (Get-Content -LiteralPath $of.FullName -Raw) -replace "`r`n", "`n"
        $b = (Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n"
        if ($a -ne $b) { Add-Violation $target "overlay drift: differs from governance/templates/overlay/$relPath" }
    }

    # 5. pipeline yaml paths exist
    foreach ($p in $repo.pipelines) {
        $py = Join-Path $folder $p.yaml
        if (-not (Test-Path -LiteralPath $py)) { Add-Violation $folder "pipeline '$($p.name)' yaml '$($p.yaml)' not found" }
    }

    # 6. consumers extend the templates repo at the pinned ref
    if ($repo.name -ne $m.azureDevOps.templatesRepository -and $repo.tier -ne 'governance') {
        foreach ($p in $repo.pipelines) {
            $py = Join-Path $folder $p.yaml
            if (-not (Test-Path -LiteralPath $py)) { continue }
            $y = Get-Content -LiteralPath $py -Raw
            if ($y -notmatch '(?m)^extends:\s*$') { Add-Violation $py 'pipeline does not use extends:'; continue }
            if ($y -notmatch 'template:\s*pipelines/extends/[a-z-]+\.yml@templates') { Add-Violation $py 'extends template must be pipelines/extends/<name>.yml@templates' }
            $expectedName = "$($m.azureDevOps.project)/$($m.azureDevOps.templatesRepository)"
            if ($y -notmatch "name:\s*$([regex]::Escape($expectedName))") { Add-Violation $py "resources.repositories must reference $expectedName" }
            $refMatch = [regex]::Match($y, 'repository:\s*templates[\s\S]*?ref:\s*(\S+)')
            if (-not $refMatch.Success) { Add-Violation $py 'templates repository resource has no ref: (pin to a tag)' }
            elseif ($refMatch.Groups[1].Value -ne $m.azureDevOps.templatesRef) { Add-Violation $py "templates ref '$($refMatch.Groups[1].Value)' differs from manifest templatesRef '$($m.azureDevOps.templatesRef)'" }
        }
    }

    # 1. relative paths escaping the folder
    $files = Get-ChildItem -LiteralPath $folder -Recurse -File -Force | Where-Object {
        $rel = [IO.Path]::GetRelativePath($folder, $_.FullName)
        $parts = $rel.Split([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        -not ($parts | Where-Object { $skipDirs -contains $_ }) -and ($textExt -contains $_.Extension.ToLowerInvariant() -or $_.Name -eq 'Dockerfile' -or $_.Name -like '*.config')
    }
    $folderFull = (Resolve-Path -LiteralPath $folder).Path.TrimEnd('\', '/')
    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if (-not $content) { continue }
        foreach ($mt in [regex]::Matches($content, '(?<![\w./\\])((?:\.\.[/\\])+)([\w@.\-\[\]{}*]+(?:[/\\][\w@.\-\[\]{}*]+)*)?')) {
            $relPath = $mt.Value
            $resolved = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relPath))
            if (-not $resolved.StartsWith($folderFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and $resolved -ne $folderFull) {
                Add-Violation $file.FullName "relative path '$relPath' escapes folder '$($repo.folder)'"
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host "`n$($errors.Count) boundary violation(s)." -ForegroundColor Red
    exit 1
}
Write-Host "Boundaries OK: $($mirrored.Count) mirrored folders checked." -ForegroundColor Green
