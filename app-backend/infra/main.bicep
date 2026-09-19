// app-backend (BFF) Container App: the only service the browser calls.
targetScope = 'resourceGroup'

@allowed(['dev', 'test', 'prod'])
param environment string
param location string = resourceGroup().location
param serviceName string = 'app-backend'
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
@description('Browser origins allowed by CORS (the Static Web App hostnames).')
param allowedOrigins array = []
param minReplicas int = 0
param maxReplicas int = 2
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

resource identityService 'Microsoft.App/containerApps@2025-01-01' existing = {
  name: 'ca-${prefix}-${environment}-identity-service'
}

resource approvalService 'Microsoft.App/containerApps@2025-01-01' existing = {
  name: 'ca-${prefix}-${environment}-approval-service'
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

var corsEnv = [
  for (origin, i) in allowedOrigins: {
    name: 'Cors__AllowedOrigins__${i}'
    value: origin
  }
]

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: appName
  location: location
  tags: union(tags, { 'meridian:environment': environment, 'meridian:service': serviceName, 'meridian:owner': 'experience-team' })
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
        corsPolicy: {
          allowedOrigins: allowedOrigins
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
          exposeHeaders: ['X-Correlation-Id']
          allowCredentials: false
        }
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
          env: concat(
            [
              { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
              { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
              { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
              { name: 'Meridian__Environment', value: environment }
              { name: 'Downstream__Identity__BaseAddress', value: 'https://${identityService.properties.configuration.ingress.fqdn}/' }
              { name: 'Downstream__Approvals__BaseAddress', value: 'https://${approvalService.properties.configuration.ingress.fqdn}/' }
            ],
            corsEnv
          )
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
                concurrentRequests: '80'
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
