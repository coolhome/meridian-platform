// Creates every queue listed in queues.json (plus a poison queue each) on the environment's
// platform storage account. Deployed by this repo's pipeline into rg-mrd-<env>-data.
param storageAccountName string

var queues = loadJsonContent('../queues.json').queues

resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2025-01-01' existing = {
  parent: storage
  name: 'default'
}

resource queue 'Microsoft.Storage/storageAccounts/queueServices/queues@2025-01-01' = [
  for q in queues: {
    parent: queueService
    name: q.name
    properties: {
      metadata: {
        messageType: q.messageType
        producer: q.producer
      }
    }
  }
]

resource poison 'Microsoft.Storage/storageAccounts/queueServices/queues@2025-01-01' = [
  for q in queues: {
    parent: queueService
    name: '${q.name}-poison'
    properties: {
      metadata: {
        messageType: q.messageType
        poisonOf: q.name
      }
    }
  }
]

output queueNames array = map(queues, q => q.name)
