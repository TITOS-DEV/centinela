// storage-systemtopic.bicep — System Topic de Event Grid sobre la cuenta de
// storage, para emitir "Microsoft.Storage.BlobCreated" cuando el analista
// sube un documento de identidad (semana 3, requerimiento 2.3).
//
// Separado de eventgrid-subscriptions.bicep a proposito: la suscripcion que
// entrega a documents-queue (disableLocalAuth=true) necesita que la
// identidad de este System Topic YA tenga el rol Service Bus Data Sender
// ANTES de crearse -- Event Grid valida el permiso de entrega de forma
// sincrona al crear la suscripcion, no solo cuando entrega el primer evento.
// Por eso el orden en main.bicep es: este modulo -> rbac.bicep -> el modulo
// que crea las eventSubscriptions.

@description('Nombre de la cuenta de storage donde se suben documentos, ya desplegada')
param storageAccountName string

@description('Región del System Topic (misma que la cuenta)')
param location string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource storageSystemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' = {
  name: 'evgt-storage-${storageAccountName}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

output storageSystemTopicName string = storageSystemTopic.name
output storageSystemTopicPrincipalId string = storageSystemTopic.identity.principalId
