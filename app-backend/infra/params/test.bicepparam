using '../main.bicep'

param environment = 'test'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'test001')
param imageTag = readEnvironmentVariable('MERIDIAN_IMAGE_TAG', 'local')
param revisionSuffix = readEnvironmentVariable('MERIDIAN_REVISION_SUFFIX', 'local')
param allowedOrigins = ['https://swa-mrd-test-app-frontend.azurestaticapps.net']
param minReplicas = 0
param maxReplicas = 2
