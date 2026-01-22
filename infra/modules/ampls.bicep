@description('Name of the Azure Monitor Private Link Scope')
param amplsName string

@description('Resource ID of the Log Analytics Workspace to link')
param workspaceId string

@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Tags to apply to resources')
param tags object = {}

resource ampls 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: amplsName
  location: 'global'  // AMPLS is a global resource
  tags: tags
  properties: {
    accessModeSettings: {
      // CRITICAL: This blocks public queries
      // Only queries from Private Endpoints will succeed
      queryAccessMode: 'PrivateOnly'
      ingestionAccessMode: 'Open'  // Allow ingestion from agents
    }
  }
}

// Link the Log Analytics Workspace to the AMPLS
resource scopedResource 'microsoft.insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'link-${workspaceName}'
  properties: {
    linkedResourceId: workspaceId
  }
}

output amplsId string = ampls.id
output amplsName string = ampls.name
