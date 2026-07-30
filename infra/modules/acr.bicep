// acr.bicep — Azure Container Registry, SKU Basic (el tier gratuito real de
// ACR: no hay un tier "F0", Basic es el mas barato con 10GB incluidos y
// cubre de sobra las ~4 imagenes/dia que produce el pipeline en 3 semanas).
// adminUserEnabled=false: nada de usuario/clave admin -- los container apps
// y el pipeline de CI/CD se autentican con su propia identidad (Managed
// Identity / OIDC) y el rol AcrPull, nunca con credenciales embebidas.

@description('Nombre único global del registro (solo alfanumérico, sin guiones)')
param registryName string

@description('Región de despliegue')
param location string

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
output registryId string = registry.id
