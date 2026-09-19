using '../queues.bicep'

param storageAccountName = 'stmrdprod${readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'prod001')}'
