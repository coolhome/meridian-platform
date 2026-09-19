param location string
param tags object
param prefix string
param environment string
param services array

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = [
  for service in services: {
    name: 'id-${prefix}-${environment}-${service}'
    location: location
    tags: union(tags, { 'meridian:service': service })
  }
]

output identities array = [
  for (service, i) in services: {
    service: service
    name: identity[i].name
    resourceId: identity[i].id
    principalId: identity[i].properties.principalId
    clientId: identity[i].properties.clientId
  }
]
