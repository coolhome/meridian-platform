using '../main.bicep'

param environment = 'prod'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'prod001')
param imageTag = readEnvironmentVariable('MERIDIAN_IMAGE_TAG', 'local')
param revisionSuffix = readEnvironmentVariable('MERIDIAN_REVISION_SUFFIX', 'local')
param minReplicas = 2
param maxReplicas = 8
param allowedOrigins = ['https://swa-mrd-prod-app-frontend.azurestaticapps.net']
