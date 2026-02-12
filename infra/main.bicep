targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (used for resource naming)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Resource group name for originations resources (LAW, AMPLS)')
param originationsResourceGroupName string = 'rg-originations-${environmentName}'

@description('Resource group name for workload resources (VNet, Functions, VMs)')
param workloadResourceGroupName string = 'rg-workload-${environmentName}'

@description('API key for the Function App')
@secure()
param functionApiKey string = newGuid()

// Tags applied to all resources
var tags = {
  'azd-env-name': environmentName
  sample: 'cross-subscription-ampls'
}

// Originations resource group (contains LAW and AMPLS)
resource originationsRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: originationsResourceGroupName
  location: location
  tags: tags
}

// Workload resource group (contains VNet, Functions, VMs)
resource workloadRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: workloadResourceGroupName
  location: location
  tags: tags
}

// Deploy Log Analytics Workspace in Originations RG
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: originationsRg
  params: {
    location: location
    workspaceName: 'law-originations-${environmentName}'
    tags: tags
  }
}

// Deploy Azure Monitor Private Link Scope in Originations RG
module ampls 'modules/ampls.bicep' = {
  name: 'ampls'
  scope: originationsRg
  params: {
    amplsName: 'ampls-originations-${environmentName}'
    workspaceId: logAnalytics.outputs.workspaceResourceId
    workspaceName: logAnalytics.outputs.workspaceName
    tags: tags
  }
}

// Deploy VNet in Workload RG
module vnet 'modules/vnet.bicep' = {
  name: 'vnet'
  scope: workloadRg
  params: {
    location: location
    vnetName: 'vnet-workload-${environmentName}'
    tags: tags
  }
}

// Deploy Private Endpoint to AMPLS in Workload RG
module privateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'private-endpoint'
  scope: workloadRg
  params: {
    location: location
    privateEndpointName: 'pe-ampls-${environmentName}'
    vnetName: vnet.outputs.vnetName
    subnetName: vnet.outputs.privateEndpointSubnetName
    amplsId: ampls.outputs.amplsId
    tags: tags
  }
}

// Deploy Azure Function App (VNet-integrated) in Workload RG
module functionApp 'modules/function-app.bicep' = {
  name: 'function-app'
  scope: workloadRg
  params: {
    location: location
    functionAppName: 'func-law-query-${environmentName}'
    vnetName: vnet.outputs.vnetName
    functionSubnetName: vnet.outputs.functionSubnetName
    workspaceResourceId: logAnalytics.outputs.workspaceResourceId
    workspaceId: logAnalytics.outputs.workspaceId
    functionApiKey: functionApiKey
    tags: tags
  }
  dependsOn: [
    privateEndpoint  // Ensure PE is ready before function tries to query
  ]
}

// Grant Log Analytics Reader to the Function App's managed identity
// Scoped to the originations RG where the workspace lives
module lawRoleAssignment 'modules/law-role-assignment.bicep' = {
  name: 'law-role-assignment'
  scope: originationsRg
  params: {
    workspaceName: 'law-originations-${environmentName}'
    principalId: functionApp.outputs.principalId
  }
  dependsOn: [
    logAnalytics
  ]
}

// Deploy sample VMs in Workload RG
module vms 'modules/vms.bicep' = {
  name: 'vms'
  scope: workloadRg
  params: {
    location: location
    vnetName: vnet.outputs.vnetName
    subnetName: vnet.outputs.workloadSubnetName
    workspaceId: logAnalytics.outputs.workspaceResourceId
    tags: tags
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output ORIGINATIONS_RESOURCE_GROUP string = originationsRg.name
output WORKLOAD_RESOURCE_GROUP string = workloadRg.name
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.workspaceId
output LOG_ANALYTICS_WORKSPACE_NAME string = logAnalytics.outputs.workspaceName
output AMPLS_ID string = ampls.outputs.amplsId
output VNET_NAME string = vnet.outputs.vnetName
output FUNCTION_APP_URL string = functionApp.outputs.functionAppUrl
output FUNCTION_APP_NAME string = functionApp.outputs.functionAppName
// Note: After deployment, configure Easy Auth on the Function App via Azure Portal.
// See blog-post.md Step 5 for detailed instructions.
