// storage.bicep — Storage Account (requerido internamente por Azure Functions para triggers/logs)
// LRS porque no necesitamos redundancia geográfica para un proyecto de 21 días con $60 de margen.

@description('Nombre único global de la cuenta de storage (solo minúsculas/números, máx 24 chars)')
param storageAccountName string

@description('Región de despliegue')
param location string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
