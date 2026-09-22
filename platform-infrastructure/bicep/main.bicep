// Meridian shared platform. One deployment per environment at subscription scope.
targetScope = 'subscription'

@description('Environment name. "shared" deploys environment-agnostic resources (container registry) plus the shared agent pool\'s prerequisites: a Consumption Container Apps environment, the agent-pool Key Vault, and the agents identity — and, behind agentPoolEnabled, the two agent-pool Container Apps jobs.')
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

@description('Deploy the self-hosted agent pool (Container Apps jobs against pool "meridian-agents") in the shared environment. Stays false until the owner has stored the azdo-agent-pat secret in the vault this template creates; the environment, identity, ACR pull and vault deploy regardless so the secret has somewhere to go.')
param agentPoolEnabled bool = false

@description('Tag of the acrmrdshared.azurecr.io/agents/azp-agent image the agent pool jobs run.')
param agentImageTag string = '1.0.0'

@description('Object id of a user (not a service principal) to grant Key Vault Secrets Officer on the agent-pool vault, so they can run az keyvault secret set for azdo-agent-pat — an RBAC vault grants Owner no data actions. Empty skips the role assignment.')
// This is an AAD object id, not a credential; @secure() would be the wrong fix for the linter's
// name-based heuristic here (it would also block passing it as a plain string in shared.bicepparam).
#disable-next-line secure-secrets-in-params
param secretsOfficerPrincipalId string = ''

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
    readerPrincipalIds: map(identities.outputs.identities, i => i.principalId)
  }
}

// One Consumption-only environment per environment name, including "shared": the agent pool
// below needs somewhere to run its Container Apps jobs, and this is the same module dev/test/prod
// already use (ADR 0007: Consumption only, no VNet, zone redundancy off).
module containerAppsEnvironment 'modules/container-apps-environment.bicep' = {
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

// ---------------------------------------------------------------- self-hosted agent pool (shared only)
// Identity, Key Vault and ACR pull deploy unconditionally in "shared" so the owner has somewhere to
// put the azdo-agent-pat secret before agentPoolEnabled flips the jobs themselves on.
module agentsIdentity 'modules/identities.bicep' = if (isShared) {
  name: 'identities-agents-${environment}'
  scope: rgPlatform
  params: {
    location: location
    tags: baseTags
    prefix: prefix
    environment: environment
    services: ['agents']
  }
}

module agentsKeyVault 'modules/key-vault.bicep' = if (isShared) {
  name: 'keyvault-${environment}'
  scope: rgPlatform
  params: {
    name: names.keyVault
    location: location
    tags: baseTags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    createAppInsightsSecret: false
    readerPrincipalIds: [agentsIdentity!.outputs.identities[0].principalId]
    secretsOfficerPrincipalId: secretsOfficerPrincipalId
  }
}

// Same role, same registry, same resource group as the registry module above: an explicit
// dependsOn because "existing" lookups create no implicit dependency, and this runs in the same
// deployment that may be creating the registry for the first time.
module agentsAcrPull 'modules/acr-pull.bicep' = if (isShared) {
  name: 'acrpull-agents-${environment}'
  scope: rgPlatform
  params: {
    registryName: containerRegistryName
    principalIds: [agentsIdentity!.outputs.identities[0].principalId]
  }
  dependsOn: [
    registry
  ]
}

module agentJobs 'modules/container-apps-jobs.bicep' = if (isShared && agentPoolEnabled) {
  name: 'agent-jobs-${environment}'
  scope: rgPlatform
  params: {
    location: location
    tags: baseTags
    prefix: prefix
    environment: environment
    environmentId: containerAppsEnvironment.outputs.id
    registryServer: '${containerRegistryName}.azurecr.io'
    identityResourceId: agentsIdentity!.outputs.identities[0].resourceId
    keyVaultSecretUri: '${agentsKeyVault!.outputs.uri}secrets/azdo-agent-pat'
    agentImage: '${containerRegistryName}.azurecr.io/agents/azp-agent:${agentImageTag}'
  }
}

// ---------------------------------------------------------------- outputs (names only; no secrets)
output resourceGroupPlatform string = rgPlatform.name
output resourceGroupApps string = isShared ? '' : names.rgApps
output resourceGroupData string = isShared ? '' : names.rgData
output logAnalyticsName string = names.logAnalytics
output appInsightsName string = names.appInsights
output keyVaultName string = names.keyVault
output containerAppsEnvironmentName string = names.containerAppsEnvironment
output storageAccountName string = isShared ? '' : names.storage
output cosmosAccountName string = isShared ? '' : names.cosmos
output containerRegistryName string = containerRegistryName
output serviceIdentities array = identities.outputs.identities
output agentPoolKeyVaultName string = isShared ? names.keyVault : ''
output agentPoolPatSecretUri string = isShared ? '${agentsKeyVault!.outputs.uri}secrets/azdo-agent-pat' : ''
output agentPoolEnvironmentName string = isShared ? names.containerAppsEnvironment : ''
output agentJobName string = isShared ? 'caj-${prefix}-${environment}-agent' : ''
output agentPlaceholderJobName string = isShared ? 'caj-${prefix}-${environment}-agent-placeholder' : ''
