// rbac.bicep — Le da a la Managed Identity del Function App exactamente los permisos que
// necesita y nada más (principio de mínimo privilegio: un Administrador audita esto en semana 3).

@description('Principal ID de la Managed Identity del Function App')
param functionPrincipalId string

@description('Nombre de la cuenta Cosmos')
param cosmosAccountName string

@description('Nombre del Event Grid Topic')
param eventGridTopicName string

@description('Nombre del Key Vault')
param keyVaultName string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' existing = {
  name: eventGridTopicName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Cosmos usa un sistema de roles propio (no el RBAC general de Azure) para acceso a datos.
// Este es el rol built-in "Cosmos DB Built-in Data Contributor" — lectura y escritura de documentos.
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

resource cosmosSqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmosAccount.id, functionPrincipalId, cosmosDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: functionPrincipalId
    scope: cosmosAccount.id
  }
}

// Event Grid Data Sender: permite publicar eventos en el topic, nada más (no leer, no administrar).
var eventGridDataSenderRoleId = 'd5a91429-5739-47e2-a06b-3470a27159e7'

resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionPrincipalId, eventGridDataSenderRoleId)
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventGridDataSenderRoleId)
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User: solo lectura de secretos, no puede crear ni borrar.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
  }
}
