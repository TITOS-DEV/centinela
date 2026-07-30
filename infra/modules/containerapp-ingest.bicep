// containerapp-ingest.bicep — API de ingesta como Container App con ingress
// HTTP publico.
//
// Métrica de escalado: peticiones concurrentes por réplica (http scale
// rule nativo de Container Apps/KEDA). Se prefirió sobre CPU porque el
// cuello de botella real de este servicio es esperar I/O de red (escritura
// en Cosmos + publicación en Event Grid), no cómputo -- bajo carga, la CPU
// de una réplica se mantiene baja mientras las requests se acumulan
// esperando esas dos llamadas. CPU habría escalado tarde o no habría
// escalado. concurrentRequests=10 fue calibrado para que el script de carga
// (scripts/load-test.sh) dispare scale-out en menos de un minuto sin
// necesitar un volumen de tráfico irreal para la demo.

@description('Nombre del Container App')
param containerAppName string

@description('Región de despliegue')
param location string

@description('Resource ID del Container Apps Environment')
param environmentId string

@description('Login server del registro (ej: acrcentinelaxxx.azurecr.io)')
param registryLoginServer string

@description('Resource ID de la identidad administrada asignada por el usuario (ya con AcrPull otorgado)')
param userAssignedIdentityId string

@description('Client ID de esa misma identidad (para managedIdentityClientId en DefaultAzureCredential)')
param managedIdentityClientId string

@description('Nombre de la imagen (sin registro, ej: ingest-api)')
param imageName string

@description('Tag de la imagen a desplegar')
param imageTag string = 'latest'

@description('Cosmos endpoint (no es secreto, es una URL)')
param cosmosEndpoint string

@description('Event Grid topic endpoint (no es secreto, es una URL)')
param eventGridTopicEndpoint string

@description('Connection string de Application Insights (clave de escritura, no de lectura de datos)')
@secure()
param appInsightsConnectionString string

@description('Réplicas mínimas. 1 evita cold-start en la demo de "transacción normal".')
param minReplicas int = 1

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
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
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
          name: 'ingest-api'
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
            { name: 'EVENTGRID_TOPIC_ENDPOINT', value: eventGridTopicEndpoint }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/healthz', port: 8080 }
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: { path: '/healthz', port: 8080 }
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-concurrency-scale'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppName string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
