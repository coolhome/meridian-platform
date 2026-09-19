#Requires -Version 7.2
<#
.SYNOPSIS
    Creates the user-assigned managed identity an environment's pipelines run as (workload
    identity federation), with the roles the platform deployment needs. Run once per
    environment by a subscription Owner; then paste the printed values into
    governance/environments/environments.json and run tooling/Initialize-AzureDevOps.ps1,
    which creates the service connection and prints the federated-credential command.
.EXAMPLE
    pwsh scripts/New-PipelineIdentity.ps1 -Environment dev -SubscriptionId 1111-... -Location eastus2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('shared', 'dev', 'test', 'prod')][string]$Environment,
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$Location,
    [string]$Prefix = 'mrd'
)
$ErrorActionPreference = 'Stop'
az account set --subscription $SubscriptionId
$rg = "rg-$Prefix-$Environment-platform"
$name = "id-$Prefix-$Environment-pipelines"

az group create --name $rg --location $Location --tags "meridian:environment=$Environment" 'meridian:owner=platform-engineering' --output none
$mi = az identity create --resource-group $rg --name $name --location $Location --output json | ConvertFrom-Json

# Contributor to deploy, RBAC Administrator to create the data-plane role assignments in main.bicep.
foreach ($role in @('Contributor', 'Role Based Access Control Administrator')) {
    az role assignment create --assignee-object-id $mi.principalId --assignee-principal-type ServicePrincipal --role $role --scope "/subscriptions/$SubscriptionId" --output none
}
$tenant = az account show --query tenantId -o tsv
$subName = az account show --query name -o tsv

Write-Host "`nPaste into governance/environments/environments.json -> environments[$Environment].azure:" -ForegroundColor Cyan
@{
    subscriptionId        = $SubscriptionId
    subscriptionName      = $subName
    tenantId              = $tenant
    identityClientId      = $mi.clientId
    identityResourceGroup = $rg
    identityName          = $name
    location              = $Location
} | ConvertTo-Json
