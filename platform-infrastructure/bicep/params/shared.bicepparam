using '../main.bicep'

param environment = 'shared'
param location = 'eastus2'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'shared01')
param containerRegistryName = 'acrmrdshared'
param allowedLocations = ['eastus2', 'centralus']
