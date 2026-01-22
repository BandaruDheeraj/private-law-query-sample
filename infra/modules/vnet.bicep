@description('Location for the VNet')
param location string

@description('Name of the Virtual Network')
param vnetName string

@description('Tags to apply to resources')
param tags object = {}

@description('Address prefix for the VNet')
param addressPrefix string = '10.0.0.0/16'

@description('Address prefix for the function subnet (Azure Functions)')
param functionSubnetPrefix string = '10.0.0.0/24'

@description('Address prefix for the workload subnet (VMs)')
param workloadSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the private endpoints subnet')
param privateEndpointSubnetPrefix string = '10.0.2.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'functions'
        properties: {
          addressPrefix: functionSubnetPrefix
          // Required for Azure Functions VNet integration
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'workload'
        properties: {
          addressPrefix: workloadSubnetPrefix
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output functionSubnetId string = vnet.properties.subnets[0].id
output functionSubnetName string = 'functions'
output workloadSubnetId string = vnet.properties.subnets[1].id
output workloadSubnetName string = 'workload'
output privateEndpointSubnetId string = vnet.properties.subnets[2].id
output privateEndpointSubnetName string = 'private-endpoints'
