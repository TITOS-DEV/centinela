// cosmos.bicep — Cosmos DB (Core SQL API), free tier, particionado por /accountId
// Justificación: la consulta dominante es "transacciones recientes de esta cuenta" (semana 2).
// Particionar por accountId hace que esa consulta caiga siempre en una sola partición lógica,
// en vez de hacer fan-out entre particiones. El free tier de Cosmos (1000 RU/s + 25GB) es
// permanente, no un trial de 30 días — por eso conviene fijarlo aquí desde el día 1 del crédito.
// Solo puede haber UNA cuenta con free tier activado por suscripción: si ya usaron el free tier
// en otro proyecto de la célula, este flag falla y hay que ponerlo en false (deja de ser gratis).

@description('Nombre único global de la cuenta Cosmos')
param cosmosAccountName string

@description('Región de despliegue')
param location string

@description('Si esta suscripción ya usó el free tier de Cosmos en otro recurso, poner en false')
param enableFreeTier bool = true

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: enableFreeTier
    consistencyPolicy: {
      // Session: cada cliente ve sus propias escrituras de inmediato (necesario porque la API
      // escribe y el scoring lee casi al instante), sin pagar el costo de Strong a nivel global.
      // No necesitamos Strong: no hay multi-región ni transacciones financieras de doble escritura.
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: []
  }
}

resource sqlDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: 'centinela'
  properties: {
    resource: {
      id: 'centinela'
    }
    // Throughput compartido a nivel de BD (400 RU/s mínimo). Con free tier, los primeros
    // 1000 RU/s de la cuenta no se cobran — este valor entra dentro de ese margen.
    options: {
      throughput: 400
    }
  }
}

resource transactionsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: sqlDatabase
  name: 'transactions'
  properties: {
    resource: {
      id: 'transactions'
      partitionKey: {
        paths: [
          '/accountId'
        ]
        kind: 'Hash'
      }
      // Índice compuesto para la consulta "transacciones de esta cuenta ordenadas por fecha"
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [ { path: '/*' } ]
        compositeIndexes: [
          [
            { path: '/accountId', order: 'ascending' }
            { path: '/originTimestamp', order: 'descending' }
          ]
        ]
      }
    }
    // Free tier cubre hasta 1000 RU/s + 25GB gratis en TODA la cuenta (no por contenedor).
    // Con throughput compartido a nivel de base de datos alcanza de sobra para el volumen del proyecto.
  }
}

output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosAccountId string = cosmosAccount.id
