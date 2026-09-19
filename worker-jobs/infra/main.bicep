// worker-jobs Container App: no ingress, KEDA-scaled on the approval-requested queue with managed identity.
targetScope = 'resourceGroup'

@allowed(['dev', 'test', 'prod'])
param environment string
param location string = resourceGroup().location
param serviceName string = 'worker-jobs'
param imageTag string
param revisionSuffix string
@description('Accepted for template parity with the other services; the worker has no ingress, so traffic weights do not apply.')
@minValue(0)
@maxValue(100)
param latestRevisionWeight int = 100
param previousRevisionName string = ''
param containerRegistry string = 'acrmrdshared.azurecr.io'
param prefix string = 'mrd'
param uniqueSuffix string
param platformResourceGroup string = 'rg-${prefix}-${environment}-platform'
param dataResourceGroup string = 'rg-${prefix}-${environment}-data'
param minReplicas int = 0
param maxReplicas int = 2
@description('KEDA azure-queue target length per replica.')
param queueLengthPerReplica int = 10
param cpu string = '0.25'
param memory string = '0.5Gi'
param tags object = {}

var appName = 'ca-${prefix}-${environment}-${serviceName}'
var storageName = toLower('st${prefix}${environment}${uniqueSuffix}')

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

resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageName
  scope: resourceGroup(dataResourceGroup)
}

resource approvalService 'Microsoft.App/containerApps@2025-01-01' existing = {
  name: 'ca-${prefix}-${environment}-approval-service'
}

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: appName
  location: location
  tags: union(tags, { 'meridian:environment': environment, 'meridian:service': serviceName, 'meridian:owner': 'approvals-team', 'meridian:previous-revision': previousRevisionName, 'meridian:latest-weight': string(latestRevisionWeight) })
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
      activeRevisionsMode: 'Single'
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
            { name: 'Messaging__QueueServiceUri', value: storage.properties.primaryEndpoints.queue }
            { name: 'Downstream__Approvals__BaseAddress', value: 'https://${approvalService.properties.configuration.ingress.fqdn}/' }
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
              initialDelaySeconds: 10
              periodSeconds: 15
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'approval-requested-queue'
            custom: {
              type: 'azure-queue'
              metadata: {
                queueName: 'approval-requested'
                queueLength: string(queueLengthPerReplica)
                accountName: storageName
                cloud: 'AzurePublicCloud'
              }
              identity: identity.id
            }
          }
        ]
      }
    }
  }
}

output name string = app.name
output fqdn string = ''
output revisionFqdn string = ''
