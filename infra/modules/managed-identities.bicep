// managed-identities.bicep — Identidades administradas ASIGNADAS POR EL USUARIO
// para ingest-api y scoring-engine.
//
// Por qué no System-Assigned (como en el resto del proyecto): un Container App
// con identidad system-assigned solo la obtiene DESPUÉS de crearse — pero la
// creación del propio Container App ya intenta descargar su imagen del ACR
// usando esa identidad. Eso es una dependencia circular: no se puede otorgar
// el rol AcrPull antes de que exista el principal, y el Container App no
// puede terminar de crearse sin poder descargar la imagen. Con identidades
// asignadas por el usuario, el principalId existe desde este módulo,
// permitiendo que rbac.bicep otorgue AcrPull ANTES de que main.bicep cree los
// Container Apps (dependsOn explícito).

@description('Región de despliegue')
param location string

@description('Sufijo único del proyecto')
param suffix string

resource ingestIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-ingest-${suffix}'
  location: location
}

resource scoringIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-scoring-${suffix}'
  location: location
}

output ingestIdentityId string = ingestIdentity.id
output ingestPrincipalId string = ingestIdentity.properties.principalId
output ingestClientId string = ingestIdentity.properties.clientId
output scoringIdentityId string = scoringIdentity.id
output scoringPrincipalId string = scoringIdentity.properties.principalId
output scoringClientId string = scoringIdentity.properties.clientId
