targetScope = 'subscription'

@description('Location for all resources')
param location string = 'eastus'

@description('Environment short name')
param environment string

@description('Project prefix')
param prefix string = 'usedcar'

@description('Azure ML registry name')
param registryName string = 'aml-enterprise-registry'

@description('Create the shared registry in this deployment')
param createRegistry bool = false

var resourceGroupName = 'rg-aml-${environment}'
var workspaceName = 'aml-ws-${environment}'
var storageAccountName = toLower('${prefix}${environment}stg01')
var keyVaultName = toLower('${prefix}-${environment}-kv')
var appInsightsName = 'appi-aml-${environment}'
var logAnalyticsName = 'log-aml-${environment}'
var containerRegistryName = toLower('${prefix}${environment}acr01')

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    environment: environment
    project: 'azure-mlops'
  }
}

module workspace './modules/workspace.bicep' = {
  name: 'workspace-${environment}'
  scope: rg
  params: {
    location: location
    workspaceName: workspaceName
    storageAccountName: storageAccountName
    keyVaultName: keyVaultName
    appInsightsName: appInsightsName
    logAnalyticsName: logAnalyticsName
    containerRegistryName: containerRegistryName
  }
}

resource registry 'Microsoft.MachineLearningServices/registries@2024-04-01' = if (createRegistry) {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

output workspaceName string = workspaceName
output resourceGroupName string = resourceGroupName
output registryNameOut string = registryName
