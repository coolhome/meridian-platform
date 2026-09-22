#Requires -Version 7.2
<#
.SYNOPSIS
    Tears down one environment's Azure resources (dev, test or prod) so the governed pipelines can
    recreate it from scratch. Never touches shared.
.DESCRIPTION
    Deletes rg-<prefix>-<env>-apps and rg-<prefix>-<env>-data outright, then empties
    rg-<prefix>-<env>-platform except for two resources that are kept on purpose:

      * the Key Vault. Purge protection (ADR 0007 keeps it on) reserves the vault name for 90 days
        after a delete, so the next deployment would fail with VaultAlreadyExists unless the template
        switched to createMode=recover. A standard vault with no traffic costs nothing, so it stays and
        the next deployment simply updates it.
      * the pipeline identity (id-<prefix>-<env>-pipelines). The environment's service connection
        federates to it; deleting it means New-PipelineIdentity.ps1, an environments.json edit and a
        bootstrap run before anything can deploy again.

    Everything else goes: Container Apps, Static Web App, Cosmos, Storage, the Container Apps
    environment, Application Insights, alerts, workbooks, action groups, the service identities, and
    the Log Analytics workspace (permanently, so no 14-day soft-deleted copy lingers). Role assignments
    the deleted service identities held on the kept Key Vault and on the shared registry are removed,
    and the environment's subscription-scope policy assignments are deleted unless -KeepPolicyAssignments.

    Reads the subscription and identity name from governance/environments/environments.json.
    Supports -WhatIf. Non-interactive callers pass -Force to skip the confirmation.
    Redeploy afterwards with: pwsh tooling/Start-EnvironmentDeploy.ps1 -Environment <env>
.EXAMPLE
    pwsh tooling/Remove-AzureEnvironment.ps1 -Environment dev -WhatIf
.EXAMPLE
    pwsh tooling/Remove-AzureEnvironment.ps1 -Environment dev -Force
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'test', 'prod')][string]$Environment,
    [string]$ManifestPath,
    [switch]$Force,
    [switch]$KeepPolicyAssignments,
    [int]$TimeoutMinutes = 45
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib' 'Meridian.Ado.psm1') -Force

$m = Get-MeridianManifest -Path $ManifestPath
$prefix = $m.platform.resourcePrefix
$envDefs = Get-MeridianGovernanceFile -Manifest $m -Key environments
$envDef = $envDefs.environments | Where-Object { $_.name -eq $Environment } | Select-Object -First 1
if (-not $envDef -or -not $envDef.PSObject.Properties['azure']) { throw "environment '$Environment' has no azure block in environments.json" }
$sub = $envDef.azure.subscriptionId
if ($sub -notmatch '^[0-9a-f-]{36}$') { throw "environment '$Environment' has no real subscription id in environments.json ($sub); nothing to tear down" }
$pipelineIdentity = $envDef.azure.identityName
$sharedRg = "rg-$prefix-shared-platform"
$registry = $m.azureDevOps.containerRegistry

function Invoke-Az {
    # az with JSON output; returns $null on a non-zero exit instead of throwing, callers decide.
    param([Parameter(ValueFromRemainingArguments)][string[]]$Args)
    $out = & az @Args -o json --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) { Write-MeridianWarn (($out | Where-Object { $_ -is [string] }) -join ' '); return $null }
    $text = ($out | Where-Object { $_ -is [string] }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 32
}

& az account set --subscription $sub --only-show-errors
$rgPlatform = "rg-$prefix-$Environment-platform"
$rgApps = "rg-$prefix-$Environment-apps"
$rgData = "rg-$prefix-$Environment-data"

# ---------------------------------------------------------------- inventory
Write-MeridianStep "inventory for $Environment (subscription $sub)"
$existing = @{}
foreach ($rg in @($rgApps, $rgData, $rgPlatform)) {
    $exists = (& az group exists --name $rg --only-show-errors) -eq 'true'
    $existing[$rg] = $exists
    if (-not $exists) { Write-MeridianInfo "$rg does not exist"; continue }
    $resources = @(Invoke-Az resource list -g $rg)
    Write-MeridianInfo "$rg ($($resources.Count) resources)"
    foreach ($r in $resources | Sort-Object type, name) { Write-MeridianInfo "    $($r.type)  $($r.name)" }
}
if (-not ($existing.Values -contains $true)) { Write-MeridianOk "nothing to tear down for $Environment"; exit 0 }

$platformResources = if ($existing[$rgPlatform]) { @(Invoke-Az resource list -g $rgPlatform) } else { @() }
$keyVault = $platformResources | Where-Object { $_.type -eq 'Microsoft.KeyVault/vaults' } | Select-Object -First 1
$pipelineMi = $platformResources | Where-Object { $_.type -eq 'Microsoft.ManagedIdentity/userAssignedIdentities' -and $_.name -eq $pipelineIdentity } | Select-Object -First 1
$serviceMis = @($platformResources | Where-Object { $_.type -eq 'Microsoft.ManagedIdentity/userAssignedIdentities' -and $_.name -ne $pipelineIdentity })
$keepIds = @(@($keyVault, $pipelineMi) | Where-Object { $_ } | ForEach-Object { $_.id })
$servicePrincipalIds = @($serviceMis | ForEach-Object { (Invoke-Az identity show --ids $_.id).principalId } | Where-Object { $_ })

$policyNames = @()
if (-not $KeepPolicyAssignments) {
    $policyNames = @(@(Invoke-Az policy assignment list --scope "/subscriptions/$sub") |
        Where-Object { $_ -and $_.name -like "$prefix-$Environment-*" -and $_.metadata -and $_.metadata.PSObject.Properties['assignedBy'] -and $_.metadata.assignedBy -like 'Meridian*' } |
        ForEach-Object { $_.name })
}

Write-Host ''
Write-Host "Plan for '$Environment':" -ForegroundColor Cyan
if ($existing[$rgApps]) { Write-Host "  delete resource group $rgApps" }
if ($existing[$rgData]) { Write-Host "  delete resource group $rgData" }
if ($existing[$rgPlatform]) {
    Write-Host "  empty resource group $rgPlatform, keeping:"
    Write-Host "    $(if ($keyVault) { $keyVault.name } else { '(no key vault found)' })  -- purge protection reserves the name for 90 days; costs nothing idle"
    Write-Host "    $(if ($pipelineMi) { $pipelineMi.name } else { "(pipeline identity $pipelineIdentity not found)" })  -- the service connection federates to it"
    Write-Host "  remove role assignments of $($servicePrincipalIds.Count) deleted service identities on the kept vault and on $registry"
}
if ($policyNames.Count) { Write-Host "  delete policy assignments: $($policyNames -join ', ')" }
Write-Host ''

if ($WhatIfPreference) { Write-MeridianOk 'what-if: no changes made'; exit 0 }
if ($Force) { $ConfirmPreference = 'None' }
if (-not $PSCmdlet.ShouldProcess("Meridian environment '$Environment' in subscription $sub", 'tear down')) { Write-MeridianWarn 'cancelled'; exit 1 }

# ---------------------------------------------------------------- 1. apps and data resource groups
$deleting = @()
foreach ($rg in @($rgApps, $rgData)) {
    if (-not $existing[$rg]) { continue }
    Write-MeridianStep "delete $rg"
    & az group delete --name $rg --yes --no-wait --only-show-errors
    if ($LASTEXITCODE -eq 0) { $deleting += $rg } else { Write-MeridianWarn "delete of $rg did not start" }
}
foreach ($rg in $deleting) {
    & az group wait --name $rg --deleted --timeout ($TimeoutMinutes * 60) --only-show-errors
    if ($LASTEXITCODE -eq 0) { Write-MeridianOk "$rg deleted" } else { Write-MeridianWarn "$rg is still deleting after $TimeoutMinutes minutes; check the portal" }
}

# ---------------------------------------------------------------- 2. platform resource group, minus the keep list
if ($existing[$rgPlatform]) {
    Write-MeridianStep "empty $rgPlatform (keeping $($keepIds.Count) resources)"
    $lawType = 'Microsoft.OperationalInsights/workspaces'
    # Deletes have ordering constraints (alerts before the App Insights they watch, apps environment before
    # the workspace it logs to). Rather than encode every dependency, delete in passes until nothing is left.
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $pass = 0
    do {
        $pass++
        $remaining = @(Invoke-Az resource list -g $rgPlatform) | Where-Object { $keepIds -notcontains $_.id -and $_.type -ne $lawType }
        if ($remaining.Count -eq 0) { break }
        Write-MeridianInfo "pass $pass`: $($remaining.Count) resources"
        # Order within a pass: monitoring rules first, then compute, then everything else.
        $ordered = $remaining | Sort-Object { switch -Wildcard ($_.type) {
                'Microsoft.Insights/scheduledqueryrules' { 0 } 'Microsoft.Insights/metricalerts' { 0 } 'Microsoft.Insights/webtests' { 0 }
                'microsoft.alertsmanagement/*' { 1 } 'Microsoft.Insights/workbooks' { 1 } 'Microsoft.Insights/actiongroups' { 2 }
                'Microsoft.App/containerApps' { 3 } 'Microsoft.App/managedEnvironments' { 4 } 'Microsoft.Insights/components' { 5 }
                default { 6 } } }
        foreach ($r in $ordered) {
            $null = & az resource delete --ids $r.id --only-show-errors 2>&1
            if ($LASTEXITCODE -eq 0) { Write-MeridianOk "deleted $($r.type) $($r.name)" } else { Write-MeridianInfo "retry later: $($r.type) $($r.name)" }
        }
    } while ((Get-Date) -lt $deadline -and $pass -lt 8)
    $left = @(Invoke-Az resource list -g $rgPlatform) | Where-Object { $keepIds -notcontains $_.id -and $_.type -ne $lawType }
    if ($left.Count) { Write-MeridianWarn "$($left.Count) resources could not be deleted: $(($left | ForEach-Object { $_.name }) -join ', ')" }

    foreach ($law in @(Invoke-Az resource list -g $rgPlatform --resource-type $lawType)) {
        # --force skips the 14-day soft-delete so a redeploy creates a fresh workspace instead of recovering old data.
        $null = & az monitor log-analytics workspace delete --resource-group $rgPlatform --workspace-name $law.name --force true --yes --only-show-errors 2>&1
        if ($LASTEXITCODE -eq 0) { Write-MeridianOk "deleted workspace $($law.name) permanently" } else { Write-MeridianWarn "workspace $($law.name) delete failed" }
    }

    # Role assignments for principals that no longer exist show as "Identity not found" forever; remove the ones we created.
    if ($servicePrincipalIds.Count) {
        $scopes = @()
        if ($keyVault) { $scopes += $keyVault.id }
        $acr = Invoke-Az acr show --name $registry --resource-group $sharedRg
        if ($acr) { $scopes += $acr.id }
        foreach ($scope in $scopes) {
            foreach ($ra in @(Invoke-Az role assignment list --scope $scope) | Where-Object { $servicePrincipalIds -contains $_.principalId }) {
                $null = & az role assignment delete --ids $ra.id --only-show-errors 2>&1
                if ($LASTEXITCODE -eq 0) { Write-MeridianOk "removed $($ra.roleDefinitionName) for deleted identity on $($scope.Split('/')[-1])" }
            }
        }
    }
}

# ---------------------------------------------------------------- 3. policy assignments
foreach ($name in $policyNames) {
    $null = & az policy assignment delete --name $name --scope "/subscriptions/$sub" --only-show-errors 2>&1
    if ($LASTEXITCODE -eq 0) { Write-MeridianOk "deleted policy assignment $name" } else { Write-MeridianWarn "policy assignment $name not deleted" }
}

Write-Host ''
Write-MeridianOk "environment '$Environment' torn down. Kept: $(($keepIds | ForEach-Object { $_.Split('/')[-1] }) -join ', ')"
Write-Host "Redeploy: pwsh tooling/Start-EnvironmentDeploy.ps1 -Environment $Environment" -ForegroundColor Cyan
