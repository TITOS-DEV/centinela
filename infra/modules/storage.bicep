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

// identity-documents: contenedor donde el analista sube el documento de
// identidad a verificar (semana 3, requerimiento 2.3). Privado — el acceso
// de Document Intelligence es via su identidad administrada (Storage Blob
// Data Reader, ver rbac.bicep), nunca por SAS ni acceso publico.
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource identityDocumentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'identity-documents'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output identityDocumentsContainerName string = identityDocumentsContainer.name
