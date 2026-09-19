using '../main.bicep'

param environment = 'test'
param location = 'eastus2'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'test001')
param containerRegistryName = 'acrmrdshared'
param allowedLocations = ['eastus2', 'centralus']
param logRetentionInDays = 30
