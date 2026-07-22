// function.bicep — Function App en plan Consumption (pago por ejecución, no por cómputo idle)
// Justificación del plan: en semana 1 solo hay una función HTTP de baja frecuencia relativa
// (comparado con un App Service Plan dedicado, que cobra 24/7 exista tráfico o no). Consumption
// es la opción que protege el crédito. Identidad administrada asignada por el sistema: así la
// función se autentica contra Cosmos, Event Grid y Key Vault sin ninguna clave en app settings.

@description('Nombre único global del Function App')
param functionAppName string

@description('Región de despliegue')
param location string

@description('Nombre de la cuenta de storage ya creada')
param storageAccountName string

@description('Cosmos endpoint (no es secreto, es una URL)')
param cosmosEndpoint string

@description('Event Grid topic endpoint (no es secreto, es una URL)')
param eventGridTopicEndpoint string

@description('URI del Key Vault')
param keyVaultUri string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${functionAppName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Application Insights es la pieza de observabilidad de punta a punta que pide el
    // proyecto (restricción #3): correlación de logs de ingesta, scoring y explicador en semana 3.
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1' // Consumption
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Linux
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|20'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
        {
          name: 'COSMOS_DATABASE'
          value: 'centinela'
        }
        {
          name: 'COSMOS_CONTAINER'
          value: 'transactions'
        }
        {
          name: 'EVENTGRID_TOPIC_ENDPOINT'
          value: eventGridTopicEndpoint
        }
        {
          name: 'KEYVAULT_URI'
          value: keyVaultUri
        }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppHostName string = functionApp.properties.defaultHostName
