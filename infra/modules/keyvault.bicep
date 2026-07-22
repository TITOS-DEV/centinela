// keyvault.bicep — Key Vault
// En semana 1 casi no hay secretos reales (Cosmos y Event Grid usan Managed Identity, sin claves).
// Lo levantamos igual desde ahora porque en semana 3 va la clave del servicio de Document
// Intelligence, y montar el Key Vault a mitad de proyecto obliga a tocar RBAC y app settings
// de nuevo. Mejor la costumbre desde el día 1: ningún secreto vive en el código ni en local.settings.json commiteado.

@description('Nombre único global del Key Vault')
param keyVaultName string

@description('Región de despliegue')
param location string

@description('Tenant ID de Entra ID')
param tenantId string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true // RBAC en vez de access policies clásicas: más fácil de auditar
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    publicNetworkAccess: 'Enabled' // private endpoints fuera de alcance
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
