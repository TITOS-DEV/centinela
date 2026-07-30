// containerappsenv.bicep — Container Apps Environment (Consumption workload
// profile, sin nodos dedicados: se paga por vCPU-s/GiB-s realmente
// consumidos, con una capa gratuita mensual). Esto es lo que reemplaza al
// "cluster gestionado" que el alcance de la semana excluye explícitamente
// (nada de AKS): Container Apps administra el plano de control por nosotros.
//
// El shared key del workspace se resuelve en tiempo de despliegue via
// listKeys() (igual que AzureWebJobsStorage en el resto del proyecto) --
// nunca queda un secreto literal en este archivo ni en el repo.

@description('Nombre del Container Apps Environment')
param environmentName string

@description('Región de despliegue')
param location string

@description('Nombre del Log Analytics Workspace ya desplegado')
param logAnalyticsWorkspaceName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output environmentId string = environment.id
output environmentName string = environment.name
