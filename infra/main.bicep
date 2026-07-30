// main.bicep — Centinela, Semana 3: contenedores, escalado, observabilidad
// Todo lo que se despliega acá se puede destruir y recrear ejecutando deploy.sh
// de nuevo. No hay ningún recurso creado a mano en el portal.
//
// Cambio de arquitectura respecto a semana 1/2: la API de ingesta y el motor
// de scoring dejan de ser Azure Functions en plan Consumption y pasan a ser
// dos imágenes de contenedor desplegadas en Azure Container Apps (ver
// docs/architecture-decisions.md). No hay Key Vault: todo el sistema se
// autentica por Managed Identity / Entra ID, sin secretos que gestionar.

targetScope = 'resourceGroup'

@description('Sufijo corto y único para nombrar recursos (ej: iniciales + 4 dígitos random)')
@minLength(3)
@maxLength(10)
param suffix string

@description('Región de despliegue')
param location string = resourceGroup().location

@description('Si esta suscripción ya tiene el free tier de Cosmos usado en otro recurso, poner en false')
param cosmosFreeTier bool = true

@description('Tag de las imagenes a desplegar (lo fija el pipeline de CI/CD con el SHA del commit)')
param imageTag string = 'latest'

@description('Email que recibe la alerta de tasa de excepciones')
param alertEmailAddress string

module storage 'modules/storage.bicep' = {
  name: 'storage-deploy'
  params: {
    storageAccountName: 'stcentinela${suffix}'
    location: location
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos-deploy'
  params: {
    cosmosAccountName: 'cosmos-centinela-${suffix}'
    location: location
    enableFreeTier: cosmosFreeTier
  }
}

module eventGrid 'modules/eventgrid.bicep' = {
  name: 'eventgrid-deploy'
  params: {
    eventGridTopicName: 'evgt-centinela-${suffix}'
    location: location
  }
}

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus-deploy'
  params: {
    serviceBusNamespaceName: 'sb-centinela-${suffix}'
    location: location
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr-deploy'
  params: {
    registryName: 'acrcentinela${suffix}'
    location: location
  }
}

module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics-deploy'
  params: {
    workspaceName: 'log-centinela-${suffix}'
    location: location
  }
}

module appInsights 'modules/appinsights.bicep' = {
  name: 'appinsights-deploy'
  params: {
    appInsightsName: 'appi-centinela-${suffix}'
    location: location
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

module documentIntelligence 'modules/documentintelligence.bicep' = {
  name: 'documentintelligence-deploy'
  params: {
    documentIntelligenceName: 'di-centinela-${suffix}'
    location: location
  }
}

module managedIdentities 'modules/managed-identities.bicep' = {
  name: 'managed-identities-deploy'
  params: {
    location: location
    suffix: suffix
  }
}

// El System Topic (con su identidad) se crea antes que rbac -- rbac necesita
// su principalId para otorgarle Service Bus Data Sender. El topic de
// transacciones ya trae su identidad desde eventgrid.bicep, sin este paso extra.
module storageSystemTopic 'modules/storage-systemtopic.bicep' = {
  name: 'storage-systemtopic-deploy'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    location: location
  }
}

// El orden importa: RBAC se resuelve ANTES que los Container Apps Y que las
// eventSubscriptions (dependsOn explícito más abajo). Con system-assigned
// identity, el Container App solo obtiene su principalId al crearse, pero la
// creación misma ya intenta descargar la imagen del ACR con esa identidad —
// un ciclo imposible de romper. Con identidades user-assigned el principalId
// existe desde este punto, así que rbac.bicep puede otorgar AcrPull antes de
// que el Container App exista y necesite tirar de esa imagen. Mismo problema
// con Event Grid: valida el permiso de entrega de forma síncrona al crear la
// eventSubscription, no solo al entregar el primer evento.
module rbac 'modules/rbac.bicep' = {
  name: 'rbac-deploy'
  params: {
    ingestPrincipalId: managedIdentities.outputs.ingestPrincipalId
    scoringPrincipalId: managedIdentities.outputs.scoringPrincipalId
    documentIntelligencePrincipalId: documentIntelligence.outputs.documentIntelligencePrincipalId
    eventGridTopicPrincipalId: eventGrid.outputs.eventGridTopicPrincipalId
    storageSystemTopicPrincipalId: storageSystemTopic.outputs.storageSystemTopicPrincipalId
    cosmosAccountName: cosmos.outputs.cosmosAccountName
    eventGridTopicName: eventGrid.outputs.eventGridTopicName
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    registryName: acr.outputs.registryName
    documentIntelligenceName: documentIntelligence.outputs.documentIntelligenceName
    storageAccountName: storage.outputs.storageAccountName
  }
}

module eventGridSubscriptions 'modules/eventgrid-subscriptions.bicep' = {
  name: 'eventgrid-subscriptions-deploy'
  params: {
    eventGridTopicName: eventGrid.outputs.eventGridTopicName
    scoringQueueId: '${serviceBus.outputs.serviceBusNamespaceId}/queues/scoring-queue'
    storageSystemTopicName: storageSystemTopic.outputs.storageSystemTopicName
    documentsQueueId: '${serviceBus.outputs.serviceBusNamespaceId}/queues/documents-queue'
  }
  dependsOn: [
    rbac
  ]
}

module containerAppsEnv 'modules/containerappsenv.bicep' = {
  name: 'containerappsenv-deploy'
  params: {
    environmentName: 'cae-centinela-${suffix}'
    location: location
    logAnalyticsWorkspaceName: logAnalytics.outputs.workspaceName
  }
}

module ingestApp 'modules/containerapp-ingest.bicep' = {
  name: 'containerapp-ingest-deploy'
  params: {
    containerAppName: 'ca-ingest-${suffix}'
    location: location
    environmentId: containerAppsEnv.outputs.environmentId
    registryLoginServer: acr.outputs.registryLoginServer
    userAssignedIdentityId: managedIdentities.outputs.ingestIdentityId
    managedIdentityClientId: managedIdentities.outputs.ingestClientId
    imageName: 'ingest-api'
    imageTag: imageTag
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    eventGridTopicEndpoint: eventGrid.outputs.eventGridTopicEndpoint
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
  dependsOn: [
    rbac
  ]
}

module scoringApp 'modules/containerapp-scoring.bicep' = {
  name: 'containerapp-scoring-deploy'
  params: {
    containerAppName: 'ca-scoring-${suffix}'
    location: location
    environmentId: containerAppsEnv.outputs.environmentId
    registryLoginServer: acr.outputs.registryLoginServer
    userAssignedIdentityId: managedIdentities.outputs.scoringIdentityId
    managedIdentityClientId: managedIdentities.outputs.scoringClientId
    imageName: 'scoring-engine'
    imageTag: imageTag
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    serviceBusNamespaceFqdn: serviceBus.outputs.serviceBusNamespaceFqdn
    serviceBusNamespaceName: serviceBus.outputs.serviceBusNamespaceName
    documentIntelligenceEndpoint: documentIntelligence.outputs.documentIntelligenceEndpoint
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
  dependsOn: [
    rbac
  ]
}

module alerts 'modules/alerts.bicep' = {
  name: 'alerts-deploy'
  params: {
    actionGroupName: 'ag-centinela-${suffix}'
    alertEmailAddress: alertEmailAddress
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    location: location
  }
}

output ingestApiFqdn string = ingestApp.outputs.fqdn
output registryLoginServer string = acr.outputs.registryLoginServer
output cosmosAccountName string = cosmos.outputs.cosmosAccountName
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output documentIntelligenceEndpoint string = documentIntelligence.outputs.documentIntelligenceEndpoint
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output storageAccountName string = storage.outputs.storageAccountName
