// eventgrid-subscriptions.bicep — conecta los dos productores de eventos
// (el topic custom de transacciones y el System Topic de blobs del storage)
// a sus colas de Service Bus consumidoras. Reemplaza el patron de semana 2
// (destino "AzureFunction") porque scoring-engine ya no es una Azure
// Function -- ahora es un contenedor plano que solo sabe leer Service Bus.
//
// Este modulo corre DESPUES de rbac.bicep (dependsOn explicito en
// main.bicep): ambas identidades (topic y system topic) ya tienen el rol
// Service Bus Data Sender antes de que estas eventSubscriptions se creen --
// Event Grid valida el permiso de forma sincrona al crear la suscripcion, no
// solo al momento de entregar el primer evento, asi que crearla antes de
// tener el rol falla inmediatamente con "Managed Identity Authorization Error".

@description('Nombre del Event Grid Topic de transacciones, ya desplegado')
param eventGridTopicName string

@description('Resource ID de la cola scoring-queue')
param scoringQueueId string

@description('Nombre del System Topic de storage, ya desplegado (ver storage-systemtopic.bicep)')
param storageSystemTopicName string

@description('Resource ID de la cola documents-queue')
param documentsQueueId string

resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' existing = {
  name: eventGridTopicName
}

// deliveryWithResourceIdentity (en vez de "destination" a secas): scoring-queue
// tiene disableLocalAuth=true, asi que Event Grid necesita autenticarse con la
// identidad administrada del topic (ver eventgrid.bicep) + el rol Service Bus
// Data Sender (rbac.bicep) para poder entregar.
resource scoringSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'scoring-subscription'
  scope: eventGridTopic
  properties: {
    deliveryWithResourceIdentity: {
      identity: {
        type: 'SystemAssigned'
      }
      destination: {
        endpointType: 'ServiceBusQueue'
        properties: {
          resourceId: scoringQueueId
        }
      }
    }
    eventDeliverySchema: 'EventGridSchema'
    filter: {
      includedEventTypes: [
        'Centinela.Transaction.Created'
      ]
    }
  }
}

resource storageSystemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' existing = {
  name: storageSystemTopicName
}

resource documentsSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  parent: storageSystemTopic
  name: 'documents-subscription'
  properties: {
    deliveryWithResourceIdentity: {
      identity: {
        type: 'SystemAssigned'
      }
      destination: {
        endpointType: 'ServiceBusQueue'
        properties: {
          resourceId: documentsQueueId
        }
      }
    }
    eventDeliverySchema: 'EventGridSchema'
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/identity-documents/'
    }
  }
}
