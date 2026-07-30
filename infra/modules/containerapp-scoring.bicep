// containerapp-scoring.bicep — motor de scoring + gestion de casos +
// explicador + verificacion documental, como worker sin ingress HTTP
// publico (consume 4 colas de Service Bus, ver serviceBusClient.js).
//
// Métrica de escalado: profundidad de la cola `scoring-queue` (KEDA scaler
// nativo azure-servicebus). Se eligió sobre CPU/RPS porque este servicio no
// tiene tráfico entrante propio -- su carga de trabajo es el backlog de
// mensajes que ingest-api produce indirectamente vía Event Grid. Escalar
// por profundidad de cola es la única métrica que refleja directamente
// "cuánto trabajo pendiente hay", y es la que KEDA soporta de forma nativa
// para Service Bus sin necesitar métricas custom.
// Autenticación del scaler vía identity (user-assigned), sin connection
// string de Service Bus como secreto.

@description('Nombre del Container App')
param containerAppName string

@description('Región de despliegue')
param location string

@description('Resource ID del Container Apps Environment')
param environmentId string

@description('Login server del registro')
param registryLoginServer string

@description('Resource ID de la identidad administrada asignada por el usuario (ya con AcrPull otorgado)')
param userAssignedIdentityId string

@description('Client ID de esa misma identidad (para managedIdentityClientId en DefaultAzureCredential)')
param managedIdentityClientId string

@description('Nombre de la imagen (sin registro, ej: scoring-engine)')
param imageName string

@description('Tag de la imagen a desplegar')
param imageTag string = 'latest'

@description('Cosmos endpoint')
param cosmosEndpoint string

@description('FQDN del namespace de Service Bus')
param serviceBusNamespaceFqdn string

@description('Nombre del namespace de Service Bus (para el scale rule)')
param serviceBusNamespaceName string

@description('Endpoint de Document Intelligence')
param documentIntelligenceEndpoint string

@description('IDs de comercio marcados como riesgosos, separados por coma')
param riskyMerchantIds string = ''

@description('Categorías de comercio marcadas como riesgosas, separadas por coma')
param riskyMerchantCategories string = 'crypto_exchange,gambling,cash_advance'

@secure()
param appInsightsConnectionString string

@description('Réplicas mínimas. 0 permite escalar a cero y ahorrar crédito cuando no hay backlog.')
param minReplicas int = 0

@description('Réplicas máximas. Acotado para proteger el crédito de la suscripción.')
param maxReplicas int = 10

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: registryLoginServer
          identity: userAssignedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'scoring-engine'
          image: '${registryLoginServer}/${imageName}:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'MANAGED_IDENTITY_CLIENT_ID', value: managedIdentityClientId }
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'COSMOS_DATABASE', value: 'centinela' }
            { name: 'COSMOS_CONTAINER', value: 'transactions' }
            { name: 'COSMOS_CASES_CONTAINER', value: 'cases' }
            { name: 'SERVICEBUS_NAMESPACE', value: serviceBusNamespaceFqdn }
            { name: 'SERVICEBUS_SCORING_QUEUE', value: 'scoring-queue' }
            { name: 'SERVICEBUS_CASES_QUEUE', value: 'cases-queue' }
            { name: 'SERVICEBUS_EXPLAINER_QUEUE', value: 'explainer-queue' }
            { name: 'SERVICEBUS_DOCUMENTS_QUEUE', value: 'documents-queue' }
            { name: 'RISKY_MERCHANT_IDS', value: riskyMerchantIds }
            { name: 'RISKY_MERCHANT_CATEGORIES', value: riskyMerchantCategories }
            { name: 'DOCUMENT_INTELLIGENCE_ENDPOINT', value: documentIntelligenceEndpoint }
            { name: 'SCORE_THRESHOLD', value: '70' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/healthz', port: 8080 }
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'servicebus-queue-depth-scale'
            custom: {
              type: 'azure-servicebus'
              // Sin "auth"/secretRef: al omitir una connection string y dar
              // solo "namespace", KEDA usa la identidad administrada
              // (user-assigned) del propio Container App para autenticarse
              // contra Service Bus, siempre que ya tenga el rol de datos
              // correspondiente (ver rbac.bicep: Service Bus Data Receiver).
              metadata: {
                queueName: 'scoring-queue'
                namespace: serviceBusNamespaceName
                messageCount: '5'
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppName string = containerApp.name
