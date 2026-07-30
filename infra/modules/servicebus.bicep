// servicebus.bicep — Service Bus Queue para casos de fraude
// Justificación: a diferencia de Event Grid (notifica, no garantiza), esta cola retiene
// el mensaje hasta que el consumidor de casos lo procesa explícitamente. Si el consumidor
// está caído, los mensajes se acumulan sin pérdida — eso es exactamente lo que exige el
// criterio de aceptación de "prueba de desacoplamiento" para la cola de casos (a diferencia
// del topic de transacciones, donde perder una notificación no es crítico porque Cosmos ya
// es la fuente de verdad).
// SKU Basic: soporta colas y autenticación por Entra ID, más barato que Standard, que solo
// hace falta si necesitáramos topics/subscriptions de Service Bus (no es el caso aquí).

@description('Nombre único global del namespace de Service Bus')
param serviceBusNamespaceName string

@description('Región de despliegue')
param location string

@description('Nombre de la cola de casos')
param casesQueueName string = 'cases-queue'

// Semana 3: 3 colas adicionales, mismo principio que cases-queue (entrega
// garantizada, at-least-once, retenida hasta ack explicito):
// - scoring-queue: recibe "Centinela.Transaction.Created" reenviado por la
//   suscripcion de Event Grid (destino Service Bus, ver eventgrid-subscriptions.bicep).
//   Es tambien la cola sobre la que escala scoring-engine (profundidad de cola).
// - explainer-queue: desacopla la generacion de la explicacion de la apertura
//   del caso (requerimiento 2.4: el explicador caido no bloquea casos nuevos).
// - documents-queue: recibe "Microsoft.Storage.BlobCreated" reenviado por el
//   System Topic de la cuenta de storage cuando el analista sube un documento.
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    disableLocalAuth: true // fuerza autenticación por Entra ID / Managed Identity, sin claves
  }
}

resource casesQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: casesQueueName
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10 // reintentos antes de mover a dead-letter
    deadLetteringOnMessageExpiration: true
  }
}

resource scoringQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'scoring-queue'
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
  }
}

resource explainerQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'explainer-queue'
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
  }
}

resource documentsQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBusNamespace
  name: 'documents-queue'
  properties: {
    lockDuration: 'PT5M' // el analisis de Document Intelligence puede tardar mas que 1 min
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
  }
}

output serviceBusNamespaceName string = serviceBusNamespace.name
// FQDN que espera @azure/service-bus, sin protocolo ni queue: "sb-centinela-xxx.servicebus.windows.net"
output serviceBusNamespaceFqdn string = '${serviceBusNamespace.name}.servicebus.windows.net'
output casesQueueName string = casesQueue.name
output scoringQueueName string = scoringQueue.name
output explainerQueueName string = explainerQueue.name
output documentsQueueName string = documentsQueue.name
output serviceBusNamespaceId string = serviceBusNamespace.id
