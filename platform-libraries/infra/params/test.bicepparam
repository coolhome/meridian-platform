using '../queues.bicep'

param storageAccountName = 'stmrdtest${readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'test001')}'
