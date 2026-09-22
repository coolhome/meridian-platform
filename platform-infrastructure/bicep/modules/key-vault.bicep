param name string
param location string
param tags object
param logAnalyticsWorkspaceId string
param appInsightsName string = ''
param readerPrincipalIds array // principals granted Key Vault Secrets User
@description('Write the App Insights connection string as a secret. False for a vault that holds no Bicep-declared secrets (e.g. the shared agent-pool vault, whose azdo-agent-pat secret is added out-of-band).')
param createAppInsightsSecret bool = true
@description('Object id of a single user (not a service principal) to grant Key Vault Secrets Officer, so they can write secrets with az keyvault secret set (a data-plane call an RBAC vault does not grant to Owner). Empty skips the role assignment.')
// This is an AAD object id, not a credential; see the same disable in main.bicep.
#disable-next-line secure-secrets-in-params
param secretsOfficerPrincipalId string = ''

var keyVaultSecretsUser = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var keyVaultSecretsOfficer = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = if (createAppInsightsSecret) {
  name: appInsightsName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// The App Insights connection string is read inside this module so it never crosses a module
// boundary as an output.
resource appInsightsSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (createAppInsightsSecret) {
  parent: keyVault
  name: 'appinsights-connection-string'
  properties: {
    value: appInsights!.properties.ConnectionString
    contentType: 'text/plain'
  }
}

resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in readerPrincipalIds: {
    name: guid(keyVault.id, principalId, keyVaultSecretsUser)
    scope: keyVault
    properties: {
      principalId: principalId
      roleDefinitionId: keyVaultSecretsUser
      principalType: 'ServicePrincipal'
    }
  }
]

// RBAC vaults grant no data actions to a subscription Owner, so writing a secret (az keyvault
// secret set) needs an explicit data-plane role. This is a human account, not a service
// identity, hence principalType 'User' rather than the 'ServicePrincipal' used above.
resource secretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(secretsOfficerPrincipalId)) {
  name: guid(keyVault.id, secretsOfficerPrincipalId, keyVaultSecretsOfficer)
  scope: keyVault
  properties: {
    principalId: secretsOfficerPrincipalId
    roleDefinitionId: keyVaultSecretsOfficer
    principalType: 'User'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
