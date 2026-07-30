// eventgrid.bicep — Event Grid Topic
// Justificación: la API tiene que responder ANTES de que termine el análisis (restricción #1
// del proyecto). Event Grid nos da pub/sub gestionado con tier gratis (~100k operaciones/mes)
// y autenticación por Entra ID (Managed Identity), así que no manejamos claves de Event Grid
// como secreto — un problema menos para el Key Vault. No usamos Service Bus porque no
// necesitamos orden estricto ni colas con reintento complejo en semana 1: el scoring en
// semana 2 es idempotente por transactionId, así que at-least-once delivery de Event Grid alcanza.

@description('Nombre del topic de Event Grid')
param eventGridTopicName string

@description('Región de despliegue')
param location string

resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: eventGridTopicName
  location: location
  identity: {
    // Necesaria para que la suscripcion "scoring-subscription" (semana 3)
    // pueda entregar eventos a la cola scoring-queue de Service Bus, que
    // tambien tiene disableLocalAuth=true: sin esta identidad y el rol
    // Service Bus Data Sender (ver rbac.bicep), Event Grid no tiene forma de
    // autenticarse contra la cola y la entrega queda encolada sin exito.
    type: 'SystemAssigned'
  }
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled' // private endpoints están fuera de alcance del proyecto
    disableLocalAuth: true // fuerza autenticación por Entra ID / Managed Identity, sin claves
  }
}

output eventGridTopicName string = eventGridTopic.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output eventGridTopicId string = eventGridTopic.id
output eventGridTopicPrincipalId string = eventGridTopic.identity.principalId
