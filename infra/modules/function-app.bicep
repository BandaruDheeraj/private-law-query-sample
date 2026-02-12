@description('Location for the Function App')
param location string

@description('Name of the Function App')
param functionAppName string

@description('Name of the VNet')
param vnetName string

@description('Name of the function subnet')
param functionSubnetName string

@description('Resource ID of the Log Analytics Workspace')
param workspaceResourceId string

@description('Customer ID (GUID) of the Log Analytics Workspace')
param workspaceId string

@description('API Key for the Function App')
@secure()
param functionApiKey string

@description('Tags to apply to resources')
param tags object = {}

// Storage account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${uniqueString(resourceGroup().id)}func'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
  }
}

// App Service Plan (Elastic Premium for VNet integration)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-${functionAppName}'
  location: location
  tags: tags
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 3
    reserved: true  // Linux
  }
}

// Reference the VNet and subnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
}

resource functionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: functionSubnetName
}

// Azure Function App with VNet integration
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: functionSubnet.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      pythonVersion: '3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      vnetRouteAllEnabled: true  // Route all traffic through VNet
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: workspaceId
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_RESOURCE_ID'
          value: workspaceResourceId
        }
        {
          name: 'FUNCTION_API_KEY'
          value: functionApiKey
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_CONTENTOVERVNET'
          value: '1'
        }
      ]
    }
  }
}

// NOTE: The Log Analytics Reader role assignment is created in main.bicep,
// scoped to the originations resource group where the workspace lives.
// This ensures the Function App's managed identity can query the workspace
// even though it's in a different resource group.

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output principalId string = functionApp.identity.principalId
