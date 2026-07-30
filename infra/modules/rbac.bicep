// rbac.bicep — RBAC de mínimo privilegio para las identidades administradas
// de la semana 3. Todo el sistema (Cosmos, Event Grid, Service Bus, ACR,
// Document Intelligence, Storage) se autentica por Entra ID / Managed
// Identity — no hay Key Vault en esta arquitectura porque no queda ningún
// secreto que gestionar (ver docs/architecture-decisions.md, sección
// "Por qué no hay Key Vault").

@description('Principal ID de la identidad administrada de ingest-api')
param ingestPrincipalId string

@description('Principal ID de la identidad administrada de scoring-engine')
param scoringPrincipalId string

@description('Principal ID de la identidad administrada de Document Intelligence')
param documentIntelligencePrincipalId string

@description('Principal ID de la identidad del Event Grid Topic de transacciones')
param eventGridTopicPrincipalId string

@description('Principal ID de la identidad del System Topic de storage (eventos de blob)')
param storageSystemTopicPrincipalId string

@description('Nombre de la cuenta Cosmos')
param cosmosAccountName string

@description('Nombre del Event Grid Topic de transacciones')
param eventGridTopicName string

@description('Nombre del namespace de Service Bus')
param serviceBusNamespaceName string

@description('Nombre del registro de contenedores')
param registryName string

@description('Nombre de la cuenta de Document Intelligence')
param documentIntelligenceName string

@description('Nombre de la cuenta de storage')
param storageAccountName string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' existing = {
  name: eventGridTopicName
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: serviceBusNamespaceName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: documentIntelligenceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// --- Roles built-in usados (mínimo privilegio, ninguno es Owner/Contributor) ---
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var eventGridDataSenderRoleId = 'd5a91429-5739-47e2-a06b-3470a27159e7'
var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
// Cosmos usa un sistema de roles propio (no el RBAC general de Azure) para acceso a datos.
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// ---- ingest-api ----
resource ingestCosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, ingestPrincipalId, 'ingest-cosmos-contributor')
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: ingestPrincipalId
    scope: cosmosAccount.id
  }
}

resource ingestEventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, ingestPrincipalId, eventGridDataSenderRoleId)
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventGridDataSenderRoleId)
    principalId: ingestPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource ingestAcrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, ingestPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: ingestPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- scoring-engine ----
resource scoringCosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, scoringPrincipalId, 'scoring-cosmos-contributor')
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: scoringPrincipalId
    scope: cosmosAccount.id
  }
}

resource scoringSbSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, scoringPrincipalId, serviceBusDataSenderRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: scoringPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource scoringSbReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, scoringPrincipalId, serviceBusDataReceiverRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: scoringPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource scoringAcrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, scoringPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: scoringPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource scoringCognitiveServicesRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(documentIntelligence.id, scoringPrincipalId, cognitiveServicesUserRoleId)
  scope: documentIntelligence
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: scoringPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Event Grid: entrega a colas de Service Bus con disableLocalAuth=true ----
// Sin esto, Event Grid publica y matchea el evento contra el filtro de la
// suscripcion, pero nunca logra entregarlo a la cola (DeliverySuccessCount
// se queda en cero indefinidamente).
resource eventGridSbSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, eventGridTopicPrincipalId, serviceBusDataSenderRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: eventGridTopicPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource storageSystemTopicSbSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, storageSystemTopicPrincipalId, serviceBusDataSenderRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: storageSystemTopicPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Document Intelligence (su propia identidad administrada) ----
// Necesita leer el blob del documento subido para poder analizarlo -- sin
// esto, la unica alternativa seria pasar SAS tokens (otro secreto de vida
// corta), lo que este proyecto evita en todo el resto del sistema.
resource docIntelStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, documentIntelligencePrincipalId, storageBlobDataReaderRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalId: documentIntelligencePrincipalId
    principalType: 'ServicePrincipal'
  }
}
