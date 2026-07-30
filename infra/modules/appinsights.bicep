// appinsights.bicep — Application Insights, workspace-based, conectado al
// Log Analytics compartido. Es la pieza de observabilidad de punta a punta
// (restricción #3 del proyecto): ingest-api y scoring-engine escriben
// requests/dependencies/customEvents/exceptions aca con `transactionId` como
// customDimension en cada evento, lo que permite reconstruir el recorrido
// completo de una transaccion via KQL sin depender de correlacion automatica
// a traves de Event Grid / Service Bus (ver services/*/src/tracing.js).

@description('Nombre del recurso de Application Insights')
param appInsightsName string

@description('Región de despliegue')
param location string

@description('Resource ID del Log Analytics Workspace')
param workspaceId string

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
    IngestionMode: 'LogAnalytics'
  }
}

output connectionString string = appInsights.properties.ConnectionString
output appInsightsName string = appInsights.name
output appInsightsId string = appInsights.id
