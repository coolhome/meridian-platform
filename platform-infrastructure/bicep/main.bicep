// Meridian shared platform. One deployment per environment at subscription scope.
targetScope = 'subscription'

@description('Environment name. "shared" deploys only environment-agnostic resources (container registry).')
@allowed(['shared', 'dev', 'test', 'prod'])
param environment string

@description('Azure region for all resources.')
param location string

@description('Short unique suffix for globally unique names (Key Vault, Storage, Cosmos).')
@minLength(3)
@maxLength(8)
param uniqueSuffix string

@description('Resource name prefix.')
param prefix string = 'mrd'

@description('Name of the shared container registry (created when environment == shared, referenced otherwise).')
param containerRegistryName string = 'acrmrdshared'

@description('Subscription that hosts the shared registry. Defaults to this subscription.')
param sharedSubscriptionId string = subscription().subscriptionId

@description('Services that receive a managed identity and data-plane roles.')
param services array = [
  'identity-service'
  'approval-service'
  'app-backend'
  'worker-jobs'
]

@description('Services allowed to send/receive Storage Queue messages.')
param queueServices array = [
  'approval-service'
  'worker-jobs'
]

@description('Services allowed to read/write Cosmos data.')
param cosmosServices array = [
  'approval-service'
]

@description('Locations permitted by policy.')
param allowedLocations array = [location]

@description('Log Analytics retention in days. 30 is the free retention window.')
param logRetentionInDays int = 30

@description('Log Analytics daily ingestion cap in GB.')
param logDailyQuotaGb int = 1

@description('Storage redundancy. LRS is the minimal-cost posture (ADR 0007).')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS'])
param storageSkuName string = 'Standard_LRS'

@description('Container registry SKU. Basic is the minimal-cost posture (ADR 0007).')
@allowed(['Basic', 'Standard', 'Premium'])
param containerRegistrySku string = 'Basic'

@description('Additional tags merged into the platform tag set.')
param tags object = {}

var isShared = environment == 'shared'
var baseTags = union(
  {
    'meridian:platform': 'meridian'
    'meridian:environment': environment
    'meridian:owner': 'platform-engineering'
    'meridian:managed-by': 'bicep'
  },
  tags
)
var names = {
  rgPlatform: 'rg-${prefix}-${environment}-platform'
  rgApps: 'rg-${prefix}-${environment}-apps'
  rgData: 'rg-${prefix}-${environment}-data'
  logAnalytics: 'log-${prefix}-${environment}'
  appInsights: 'appi-${prefix}-${environment}'
  keyVault: 'kv-${prefix}-${environment}-${uniqueSuffix}'
  containerAppsEnvironment: 'cae-${prefix}-${environment}'
  storage: toLower('st${prefix}${environment}${uniqueSuffix}')
  cosmos: 'cosmos-${prefix}-${environment}-${uniqueSuffix}'
}

// ---------------------------------------------------------------- resource groups
resource rgPlatform 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.rgPlatform
  location: location
  tags: baseTags
}

resource rgApps 'Microsoft.Resources/resourceGroups@2024-03-01' = if (!isShared) {
  name: names.rgApps
  location: location
  tags: baseTags
}

resource rgData 'Microsoft.Resources/resourceGroups@2024-03-01' = if (!isShared) {
  name: names.rgData
  location: location
  tags: baseTags
}

// ---------------------------------------------------------------- governance
module policy 'modules/policy-assignments.bicep' = {
  name: 'policy-${environment}'
  params: {
    environment: environment
    prefix: prefix
    allowedLocations: allowedLocations
  }
}

// ---------------------------------------------------------------- shared foundations
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-${environment}'
  scope: rgPlatform
  params: {
    location: location
    tags: baseTags
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    retentionInDays: logRetentionInDays
    dailyQuotaGb: logDailyQuotaGb
  }
}

module identities 'modules/identities.bicep' = {
  name: 'identities-${environment}'
  scope: rgPlatform
  params: {
    location: location
    tags: baseTags
    prefix: prefix
    environment: environment
    services: services
  }
}

module registry 'modules/container-registry.bicep' = if (isShared) {
  name: 'registry-${environment}'
  scope: rgPlatform
  params: {
    name: containerRegistryName
    skuName: containerRegistrySku
    location: location
    tags: baseTags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

// ---------------------------------------------------------------- per-environment resources
module keyVault 'modules/key-vault.bicep' = if (!isShared) {
  name: 'keyvault-${environment}'
  scope: rgPlatform
  params: {
    name: names.keyVault
    location: location
    tags: baseTags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    appInsightsName: monitoring.outputs.appInsightsName
    secretsUserPrincipalIds: map(identities.outputs.identities, i => i.principalId)
  }
}

module containerAppsEnvironment 'modules/container-apps-environment.bicep' = if (!isShared) {
  name: 'cae-${environment}'
  scope: rgPlatform
  params: {
    name: names.containerAppsEnvironment
    location: location
    tags: baseTags
    logAnalyticsName: monitoring.outputs.logAnalyticsName
  }
}

module storage 'modules/storage.bicep' = if (!isShared) {
  name: 'storage-${environment}'
  scope: rgData
  params: {
    name: names.storage
    location: location
    tags: baseTags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    skuName: storageSkuName
    queueContributorPrincipalIds: map(filter(identities.outputs.identities, i => contains(queueServices, i.service)), i => i.principalId)
  }
}

module cosmos 'modules/cosmos.bicep' = if (!isShared) {
  name: 'cosmos-${environment}'
  scope: rgData
  params: {
    name: names.cosmos
    location: location
    tags: baseTags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    dataContributorPrincipalIds: map(filter(identities.outputs.identities, i => contains(cosmosServices, i.service)), i => i.principalId)
  }
}

module acrPull 'modules/acr-pull.bicep' = if (!isShared) {
  name: 'acrpull-${environment}'
  scope: resourceGroup(sharedSubscriptionId, 'rg-${prefix}-shared-platform')
  params: {
    registryName: containerRegistryName
    principalIds: map(identities.outputs.identities, i => i.principalId)
  }
}

// ---------------------------------------------------------------- outputs (names only; no secrets)
output resourceGroupPlatform string = rgPlatform.name
output resourceGroupApps string = isShared ? '' : names.rgApps
output resourceGroupData string = isShared ? '' : names.rgData
output logAnalyticsName string = names.logAnalytics
output appInsightsName string = names.appInsights
output keyVaultName string = isShared ? '' : names.keyVault
output containerAppsEnvironmentName string = isShared ? '' : names.containerAppsEnvironment
output storageAccountName string = isShared ? '' : names.storage
output cosmosAccountName string = isShared ? '' : names.cosmos
output containerRegistryName string = containerRegistryName
output serviceIdentities array = identities.outputs.identities
