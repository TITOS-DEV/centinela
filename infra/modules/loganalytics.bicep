// loganalytics.bicep — Log Analytics Workspace, backend de Application Insights
// (modo workspace-based, el unico soportado desde 2022) y del Container Apps
// Environment (los logs de stdout/stderr de los contenedores llegan aca).
// SKU PerGB2018: pago solo por lo ingerido, sin compromiso. Los primeros 5GB/mes
// por workspace son gratis de forma permanente (parte del free tier de Azure
// Monitor) — ver docs/observability.md para el consumo estimado del proyecto.

@description('Nombre del Log Analytics Workspace')
param workspaceName string

@description('Región de despliegue')
param location string

@description('Retencion en dias. 30 es el minimo sin costo adicional de retencion extendida.')
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

output workspaceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
output workspaceName string = workspace.name
