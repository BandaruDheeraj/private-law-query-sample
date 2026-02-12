@description('Name of the Log Analytics Workspace')
param workspaceName string

@description('Principal ID of the Function App managed identity')
param principalId string

// Reference the existing workspace in this resource group
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

// Grant Log Analytics Reader role scoped to the workspace
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, principalId, 'Log Analytics Reader')
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
