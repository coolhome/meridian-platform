using '../main.bicep'

param environment = 'dev'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'dev001')
param imageTag = readEnvironmentVariable('MERIDIAN_IMAGE_TAG', 'local')
param revisionSuffix = readEnvironmentVariable('MERIDIAN_REVISION_SUFFIX', 'local')
param allowedOrigins = ['https://swa-mrd-dev-app-frontend.azurestaticapps.net']
param minReplicas = 0
param maxReplicas = 2
