using '../main.bicep'

param environment = 'dev'
param location = 'eastus2'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'dev001')
param containerRegistryName = 'acrmrdshared'
param allowedLocations = ['eastus2', 'centralus']
param logRetentionInDays = 30
