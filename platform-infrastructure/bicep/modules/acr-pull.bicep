// Deployed at the scope of the shared registry's resource group (possibly another subscription).
param registryName string
param principalIds array

var acrPull = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = {
  name: registryName
}

resource pull 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in principalIds: {
    name: guid(registry.id, principalId, acrPull)
    scope: registry
    properties: {
      principalId: principalId
      roleDefinitionId: acrPull
      principalType: 'ServicePrincipal'
    }
  }
]
