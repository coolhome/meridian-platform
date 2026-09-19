using '../queues.bicep'

param storageAccountName = 'stmrddev${readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'dev001')}'
