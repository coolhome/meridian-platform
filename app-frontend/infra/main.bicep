// app-frontend Static Web App. Content is uploaded by the pipeline; this creates the resource.
targetScope = 'resourceGroup'

@allowed(['dev', 'test', 'prod'])
param environment string
@description('Static Web Apps is available in a limited set of regions; keep it near the API region.')
param location string = 'eastus2'
param serviceName string = 'app-frontend'
param prefix string = 'mrd'
@allowed(['Free', 'Standard'])
param skuName string = 'Free'
param tags object = {}

resource site 'Microsoft.Web/staticSites@2023-12-01' = {
  name: 'swa-${prefix}-${environment}-${serviceName}'
  location: location
  tags: union(tags, { 'meridian:environment': environment, 'meridian:service': serviceName, 'meridian:owner': 'experience-team' })
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
    publicNetworkAccess: 'Enabled'
  }
}

output name string = site.name
output defaultHostname string = site.properties.defaultHostname
