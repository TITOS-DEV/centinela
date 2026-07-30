// alerts.bicep — Alerta de Azure Monitor sobre tasa de excepciones.
//
// Condición: más de 3 excepciones registradas (en cualquiera de los 4
// servicios: ingest-api, score-worker, case-worker, explainer-worker,
// document-worker — todos escriben AppExceptions con `stage` como
// customDimension, ver services/*/src/tracing.js) en una ventana de 5
// minutos.
//
// Justificación del umbral: una excepción aislada puede ser un timeout
// transitorio de red que un reintento resuelve solo (Service Bus reintenta
// automaticamente hasta maxDeliveryCount). Pero más de 3 en 5 minutos ya no
// es ruido — indica una falla sistemica (una dependencia caida, una regla
// de negocio rota, cuota de Document Intelligence agotada) que un
// reintento automático no va a resolver y que requiere que un humano mire
// los logs. Elegimos tasa de excepciones de negocio sobre métricas de
// infraestructura (CPU, memoria) porque una transacción puede fallar
// silenciosamente sin que ningún contenedor se vea "sobrecargado" — la
// excepción es la señal más directa de que un caso no se abrió cuando debía.

@description('Nombre de la Action Group')
param actionGroupName string

@description('Email que recibe la notificación de alerta')
param alertEmailAddress string

@description('Resource ID del Log Analytics Workspace (donde vive Application Insights, workspace-based)')
param logAnalyticsWorkspaceId string

@description('Región de despliegue. Scheduled query rules son globales en la práctica, pero Azure exige una región válida.')
param location string = 'global'

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'centinela'
    enabled: true
    emailReceivers: [
      {
        name: 'analista-oncall'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

resource exceptionRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-tasa-excepciones-centinela'
  location: location
  properties: {
    displayName: 'Centinela: tasa de excepciones elevada'
    description: 'Mas de 3 excepciones en 5 minutos en el pipeline de scoring/casos/explicador/documentos.'
    severity: 2
    enabled: true
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'AppExceptions | summarize count()'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 3
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

output actionGroupId string = actionGroup.id
