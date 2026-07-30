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

output serviceBusNamespaceName string = serviceBusNamespace.name
// FQDN que espera @azure/service-bus, sin protocolo ni queue: "sb-centinela-xxx.servicebus.windows.net"
output serviceBusNamespaceFqdn string = '${serviceBusNamespace.name}.servicebus.windows.net'
output casesQueueName string = casesQueue.name
output serviceBusNamespaceId string = serviceBusNamespace.id
