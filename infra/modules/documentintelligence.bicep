// documentintelligence.bicep — Azure AI Document Intelligence, tier F0
// (gratuito, permanente): 500 páginas/mes, límite verificado en semana 1
// contra el volumen esperado de documentos de verificación de identidad
// (ver docs/document-verification.md).
//
// Identidad administrada propia: Document Intelligence necesita LEER el blob
// del documento subido por el analista. En vez de generar SAS tokens (otro
// secreto de vida corta que gestionar), se le da a esta identidad el rol
// "Storage Blob Data Reader" sobre la cuenta de storage (ver rbac.bicep) y se
// le pasa solo la URL del blob -- Document Intelligence resuelve el acceso
// via Entra ID, sin ninguna clave en el payload de la llamada.

@description('Nombre único global de la cuenta de Document Intelligence')
param documentIntelligenceName string

@description('Región de despliegue (debe soportar el tier F0)')
param location string

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceName
  location: location
  kind: 'FormRecognizer'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'F0'
  }
  properties: {
    customSubDomainName: documentIntelligenceName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true // fuerza autenticación por Entra ID, sin claves de API
  }
}

output documentIntelligenceName string = documentIntelligence.name
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint
output documentIntelligencePrincipalId string = documentIntelligence.identity.principalId
