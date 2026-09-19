// Alerts, availability tests and the platform workbook for one environment.
targetScope = 'resourceGroup'

@allowed(['dev', 'test', 'prod'])
param environment string
param location string = resourceGroup().location
param prefix string = 'mrd'
param services array = [
  'identity-service'
  'approval-service'
  'app-backend'
  'worker-jobs'
]
@description('Services with public health endpoints to probe.')
param probedServices array = [
  'app-backend'
]
param alertEmail string
@minValue(1)
param failedRequestPercentThreshold int = 5
@minValue(1)
param exceptionCountThreshold int = 20
@minValue(0)
@maxValue(4)
param severity int = 2
param tags object = {}

var appsResourceGroup = 'rg-${prefix}-${environment}-apps'
var appInsightsName = 'appi-${prefix}-${environment}'
var baseTags = union({ 'meridian:environment': environment, 'meridian:owner': 'sre' }, tags)

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${prefix}-${environment}-sre'
  location: 'global'
  tags: baseTags
  properties: {
    groupShortName: take('mrd${environment}sre', 12)
    enabled: true
    emailReceivers: [
      {
        name: 'sre'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Failed request rate per service (cloud_RoleName is set by Meridian.ServiceDefaults).
resource failedRequests 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = [
  for service in services: {
    name: 'alert-${prefix}-${environment}-${service}-failed-requests'
    location: location
    tags: baseTags
    properties: {
      displayName: '${service}: failed request rate above ${failedRequestPercentThreshold}%'
      severity: severity
      enabled: true
      evaluationFrequency: 'PT15M'
      windowSize: 'PT15M'
      scopes: [appInsights.id]
      criteria: {
        allOf: [
          {
            query: 'requests | where cloud_RoleName == "${service}" | summarize total = count(), failed = countif(success == false) | extend failedPercent = iff(total == 0, 0.0, 100.0 * failed / total) | project failedPercent'
            timeAggregation: 'Average'
            metricMeasureColumn: 'failedPercent'
            operator: 'GreaterThan'
            threshold: failedRequestPercentThreshold
            failingPeriods: {
              numberOfEvaluationPeriods: 2
              minFailingPeriodsToAlert: 2
            }
          }
        ]
      }
      autoMitigate: true
      actions: {
        actionGroups: [actionGroup.id]
      }
    }
  }
]

resource exceptionSpike 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = [
  for service in services: {
    name: 'alert-${prefix}-${environment}-${service}-exceptions'
    location: location
    tags: baseTags
    properties: {
      displayName: '${service}: more than ${exceptionCountThreshold} exceptions in 15 minutes'
      severity: severity
      enabled: true
      evaluationFrequency: 'PT15M'
      windowSize: 'PT15M'
      scopes: [appInsights.id]
      criteria: {
        allOf: [
          {
            query: 'exceptions | where cloud_RoleName == "${service}" | summarize n = count() | project n'
            timeAggregation: 'Total'
            metricMeasureColumn: 'n'
            operator: 'GreaterThan'
            threshold: exceptionCountThreshold
            failingPeriods: {
              numberOfEvaluationPeriods: 1
              minFailingPeriodsToAlert: 1
            }
          }
        ]
      }
      autoMitigate: true
      actions: {
        actionGroups: [actionGroup.id]
      }
    }
  }
]

// Container App replica restarts (metric alert on the app resource in the apps resource group).
resource restarts 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for service in services: {
    name: 'alert-${prefix}-${environment}-${service}-restarts'
    location: 'global'
    tags: baseTags
    properties: {
      description: '${service}: replicas restarting'
      severity: severity
      enabled: true
      evaluationFrequency: 'PT5M'
      windowSize: 'PT15M'
      scopes: [resourceId(appsResourceGroup, 'Microsoft.App/containerApps', 'ca-${prefix}-${environment}-${service}')]
      targetResourceType: 'Microsoft.App/containerApps'
      targetResourceRegion: location
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [
          {
            name: 'restarts'
            metricNamespace: 'Microsoft.App/containerApps'
            metricName: 'RestartCount'
            operator: 'GreaterThan'
            threshold: 3
            timeAggregation: 'Maximum'
            criterionType: 'StaticThresholdCriterion'
          }
        ]
      }
      autoMitigate: true
      actions: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
]

// Standard availability tests against /health/live for public services.
resource webTest 'Microsoft.Insights/webtests@2022-06-15' = [
  for service in probedServices: {
    name: 'avail-${prefix}-${environment}-${service}'
    location: location
    tags: union(baseTags, { 'hidden-link:${appInsights.id}': 'Resource' })
    kind: 'standard'
    properties: {
      SyntheticMonitorId: 'avail-${prefix}-${environment}-${service}'
      Name: '${service} health (${environment})'
      Enabled: true
      Frequency: 900
      Timeout: 30
      Kind: 'standard'
      RetryEnabled: true
      Locations: [
        { Id: 'us-va-ash-azr' }
      ]
      Request: {
        RequestUrl: 'https://ca-${prefix}-${environment}-${service}.${environment}.placeholder.azurecontainerapps.io/health/live'
        HttpVerb: 'GET'
        ParseDependentRequests: false
      }
      ValidationRules: {
        ExpectedHttpStatusCode: 200
        SSLCheck: true
        SSLCertRemainingLifetimeCheck: 14
      }
    }
  }
]

resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for (service, i) in probedServices: {
    name: 'alert-${prefix}-${environment}-${service}-availability'
    location: 'global'
    tags: baseTags
    properties: {
      description: '${service}: availability below 99% (probe location failing)'
      severity: 1
      enabled: true
      evaluationFrequency: 'PT5M'
      windowSize: 'PT15M'
      scopes: [webTest[i].id, appInsights.id]
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
        webTestId: webTest[i].id
        componentId: appInsights.id
        failedLocationCount: 1
      }
      autoMitigate: true
      actions: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
]

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'platform-overview', environment)
  location: location
  tags: baseTags
  kind: 'shared'
  properties: {
    displayName: 'Meridian platform overview (${environment})'
    category: 'workbook'
    sourceId: appInsights.id
    serializedData: loadTextContent('../workbooks/platform-overview.workbook.json')
  }
}

output actionGroupId string = actionGroup.id
