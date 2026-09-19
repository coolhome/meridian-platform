#Requires -Version 7.2
<#
.SYNOPSIS
    Registers the base-image ACR Task against the Azure Repos mirror of this repository,
    with base-image-update triggers on. Run once per registry by Platform Engineering.
.EXAMPLE
    pwsh scripts/Register-AcrTasks.ps1 -Registry acrmrdshared -RepoUrl https://dev.azure.com/CHANGE-ME/Meridian/_git/meridian-containers -Pat $env:AZDO_PAT
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Registry,
    [Parameter(Mandatory)][string]$RepoUrl,
    [Parameter(Mandatory)][string]$Pat,
    [string]$Branch = 'main'
)
$ErrorActionPreference = 'Stop'

az acr task create `
    --registry $Registry `
    --name base-images `
    --context "$RepoUrl#$Branch" `
    --file acr-tasks/base-images.yaml `
    --git-access-token $Pat `
    --base-image-trigger-enabled true `
    --base-image-trigger-type Runtime `
    --commit-trigger-enabled false `
    --pull-request-trigger-enabled false `
    --platform linux/amd64 `
    --output table

Write-Host 'Task registered. Trigger a first run with: az acr task run --registry' $Registry '--name base-images'
