// identity-service Container App. Service-owned; references platform resources with `existing`.
targetScope = 'resourceGroup'

@allowed(['dev', 'test', 'prod'])
param environment string
param location string = resourceGroup().location
param serviceName string = 'identity-service'
param imageTag string
param revisionSuffix string
@minValue(0)
@maxValue(100)
param latestRevisionWeight int = 100
param previousRevisionName string = ''
param containerRegistry string = 'acrmrdshared.azurecr.io'
param prefix string = 'mrd'
param uniqueSuffix string
param platformResourceGroup string = 'rg-${prefix}-${environment}-platform'
param minReplicas int = 1
param maxReplicas int = 3
param cpu string = '0.25'
param memory string = '0.5Gi'
param tags object = {}

var appName = 'ca-${prefix}-${environment}-${serviceName}'
var isProd = environment == 'prod'

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: 'cae-${prefix}-${environment}'
  scope: resourceGroup(platformResourceGroup)
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-${prefix}-${environment}-${serviceName}'
  scope: resourceGroup(platformResourceGroup)
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: 'kv-${prefix}-${environment}-${uniqueSuffix}'
  scope: resourceGroup(platformResourceGroup)
}

var traffic = empty(previousRevisionName)
  ? [
      {
        latestRevision: true
        weight: 100
      }
    ]
  : [
      {
        latestRevision: true
        weight: latestRevisionWeight
      }
      {
        revisionName: previousRevisionName
        weight: 100 - latestRevisionWeight
      }
    ]

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: appName
  location: location
  tags: union(tags, { 'meridian:environment': environment, 'meridian:service': serviceName, 'meridian:owner': 'identity-team' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: isProd ? 'Multiple' : 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
        traffic: traffic
      }
      registries: [
        {
          server: containerRegistry
          identity: identity.id
        }
      ]
      secrets: [
        {
          name: 'appinsights-connection-string'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/appinsights-connection-string'
          identity: identity.id
        }
      ]
    }
    template: {
      revisionSuffix: revisionSuffix
      containers: [
        {
          name: serviceName
          image: '${containerRegistry}/services/${serviceName}:${imageTag}'
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
            { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
            { name: 'Meridian__Environment', value: environment }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health/live', port: 8080 }
              initialDelaySeconds: 5
              periodSeconds: 15
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health/ready', port: 8080 }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output revisionFqdn string = '${appName}--${revisionSuffix}.${containerAppsEnvironment.properties.defaultDomain}'
