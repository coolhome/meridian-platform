using '../main.bicep'

param environment = 'prod'
param location = 'eastus2'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'prod001')
param containerRegistryName = 'acrmrdshared'
param allowedLocations = ['eastus2', 'centralus']
param logRetentionInDays = 30
