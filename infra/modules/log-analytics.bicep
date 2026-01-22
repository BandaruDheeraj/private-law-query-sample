@description('Location for the Log Analytics Workspace')
param location string

@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Tags to apply to resources')
param tags object = {}

@description('Retention period in days')
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    // CRITICAL: Disable public network access for queries
    // This is what makes the Private Link pattern necessary
    publicNetworkAccessForQuery: 'Disabled'
    publicNetworkAccessForIngestion: 'Enabled'  // Allow ingestion from Azure Monitor Agent
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceId string = workspace.properties.customerId
output workspaceName string = workspace.name
output workspaceResourceId string = workspace.id
