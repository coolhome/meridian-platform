#Requires -Version 7.2
<#
.SYNOPSIS
    Compiles every consumer pipeline against a candidate templates ref using the pipelines
    preview API (no run is queued). Run before tagging a new templates version.
.DESCRIPTION
    Without -ConsumerRoot, each consumer's pipeline YAML is whatever is on the mirror's default
    branch (the preview API compiles resources.repositories.self at its current head); only the
    templates ref is overridden. With -ConsumerRoot, the consumer YAML is read from a local
    checkout instead (<ConsumerRoot>/<repo folder>/<pipeline yaml path>, the same manifest ->
    file mapping New-AdoPipelines.ps1 uses: repos[].folder + repos[].pipelines[].yaml) and sent
    as yamlOverride, so a consumer entry file that has not been pushed to any mirror yet can
    still be proven against a candidate templates ref.
.PARAMETER ConsumerRoot
    Local repository root to read consumer pipeline YAML from. Omit to compile the mirror's
    default branch as today.
.PARAMETER ShowExpanded
    Write the preview response's finalYaml for each consumer to
    $env:TEMP/meridian-preview/<pipeline>.yml and print the paths.
.PARAMETER PipelineName
    Limit the run to these manifest pipeline names (repos[].pipelines[].name). Default: every
    consumer pipeline in the manifest.
.EXAMPLE
    pwsh tooling/Test-PipelineTemplates.ps1 -TemplatesRef refs/heads/feature/new-scan
.EXAMPLE
    pwsh tooling/Test-PipelineTemplates.ps1 -TemplatesRef refs/tags/v1.1.0 `
        -ConsumerRoot C:\work\meridian -PipelineName app-frontend-cicd -ShowExpanded
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TemplatesRef,
    [string]$ManifestPath,
    [string]$Pat,
    [string]$ConsumerRoot,
    [switch]$ShowExpanded,
    [string[]]$PipelineName
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

if ($ConsumerRoot) {
    if (-not (Test-Path -LiteralPath $ConsumerRoot -PathType Container)) { throw "ConsumerRoot '$ConsumerRoot' does not exist." }
    $ConsumerRoot = (Resolve-Path -LiteralPath $ConsumerRoot).Path
}

$m = Get-MeridianManifest -Path $ManifestPath
$null = Connect-MeridianAdo -Manifest $m -Pat $Pat

# Print the request body's shape once, with the YAML text elided, so a malformed shape (an
# [[...]]-style double wrap, a misplaced key) is visible without scrolling past a whole file.
$shapeSample = @{ previewRun = $true; resources = @{ repositories = @{ templates = @{ refName = $TemplatesRef } } } }
if ($ConsumerRoot) { $shapeSample.yamlOverride = '<local pipeline YAML, elided>' }
Write-MeridianInfo "request body shape: $($shapeSample | ConvertTo-Json -Depth 6 -Compress)"

$expandedDir = $null
if ($ShowExpanded) {
    $expandedDir = Join-Path $env:TEMP 'meridian-preview'
    New-Item -ItemType Directory -Path $expandedDir -Force | Out-Null
}

$failed = 0
$tested = 0
foreach ($repo in Get-MeridianMirroredRepos -Manifest $m) {
    if ($repo.name -eq $m.azureDevOps.templatesRepository -or $repo.tier -eq 'governance') { continue }
    foreach ($p in $repo.pipelines) {
        if ($PipelineName -and $PipelineName.Count -gt 0 -and ($PipelineName -notcontains $p.name)) { continue }
        $def = Get-AdoPipelineDefinition -Name $p.name
        if (-not $def) { Write-MeridianWarn "$($p.name) not found"; continue }

        $body = @{ previewRun = $true; resources = @{ repositories = @{ templates = @{ refName = $TemplatesRef } } } }
        $source = 'mirror main'
        if ($ConsumerRoot) {
            # Same manifest -> file mapping New-AdoPipelines.ps1 uses to register the pipeline
            # (repo.folder + pipeline.yaml under repos[] in repos.manifest.json).
            $localPath = Join-Path $ConsumerRoot (Join-Path $repo.folder $p.yaml)
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                $failed++
                Write-Host "FAIL $($p.name): local YAML not found at $localPath" -ForegroundColor Red
                continue
            }
            $body.yamlOverride = Get-Content -LiteralPath $localPath -Raw
            $source = "local file $localPath"
        }
        Write-MeridianInfo "$($p.name): source = $source"
        $tested++

        try {
            $resp = Invoke-AdoRest -Method POST -ProjectScoped -Path "pipelines/$($def.id)/preview" -Body $body
            Write-MeridianOk $p.name
            if ($ShowExpanded) {
                $finalYaml = if ($resp.PSObject.Properties['finalYaml']) { $resp.finalYaml } else { $null }
                if ($finalYaml) {
                    $outPath = Join-Path $expandedDir "$($p.name).yml"
                    Set-Content -LiteralPath $outPath -Value $finalYaml -NoNewline
                    Write-MeridianInfo "expanded YAML: $outPath"
                }
                else {
                    Write-MeridianWarn "$($p.name): preview response had no finalYaml"
                }
            }
        }
        catch {
            $failed++
            Write-Host "FAIL $($p.name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
if ($tested -eq 0) { Write-MeridianWarn 'no consumers matched (check -PipelineName)' }
if ($failed) { Write-Host "$failed consumer(s) failed to compile against $TemplatesRef" -ForegroundColor Red; exit 1 }
Write-Host "All consumers compile against $TemplatesRef" -ForegroundColor Green
