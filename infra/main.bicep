// main.bicep — Centinela, Semana 1: Fundamentos
// Todo lo que se despliega acá se puede destruir y recrear ejecutando deploy.sh de nuevo.
// No hay ningún recurso que se haya creado a mano en el portal.

targetScope = 'resourceGroup'

@description('Sufijo corto y único para nombrar recursos (ej: iniciales + 4 dígitos random)')
@minLength(3)
@maxLength(10)
param suffix string

@description('Región de despliegue')
param location string = resourceGroup().location

@description('Si esta suscripción ya tiene el free tier de Cosmos usado en otro recurso, poner en false')
param cosmosFreeTier bool = true

var tenantId = subscription().tenantId

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

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deploy'
  params: {
    keyVaultName: 'kv-centinela-${suffix}'
    location: location
    tenantId: tenantId
  }
}

module functionApp 'modules/function.bicep' = {
  name: 'function-deploy'
  params: {
    functionAppName: 'func-centinela-${suffix}'
    location: location
    storageAccountName: storage.outputs.storageAccountName
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    eventGridTopicEndpoint: eventGrid.outputs.eventGridTopicEndpoint
    keyVaultUri: keyVault.outputs.keyVaultUri
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'rbac-deploy'
  params: {
    functionPrincipalId: functionApp.outputs.functionAppPrincipalId
    cosmosAccountName: cosmos.outputs.cosmosAccountName
    eventGridTopicName: eventGrid.outputs.eventGridTopicName
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output functionAppUrl string = 'https://${functionApp.outputs.functionAppHostName}'
output cosmosAccountName string = cosmos.outputs.cosmosAccountName
output eventGridTopicName string = eventGrid.outputs.eventGridTopicName
output keyVaultName string = keyVault.outputs.keyVaultName
