@description('Location for the Private Endpoint')
param location string

@description('Name of the Private Endpoint')
param privateEndpointName string

@description('Name of the VNet')
param vnetName string

@description('Name of the subnet for Private Endpoints')
param subnetName string

@description('Resource ID of the Azure Monitor Private Link Scope')
param amplsId string

@description('Tags to apply to resources')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: subnetName
}

// Private Endpoint to connect to AMPLS
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'ampls-connection'
        properties: {
          privateLinkServiceId: amplsId
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
  }
}

// Private DNS Zones for Azure Monitor
resource privateDnsZoneMonitor 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.monitor.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneOms 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.oms.opinsights.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneOds 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.ods.opinsights.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneAgentSvc 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.agentsvc.azure-automation.net'
  location: 'global'
  tags: tags
}

// Link DNS zones to VNet
resource vnetLinkMonitor 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneMonitor
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource vnetLinkOms 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneOms
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource vnetLinkOds 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneOds
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource vnetLinkAgentSvc 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZoneAgentSvc
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// DNS zone groups for the private endpoint
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'monitor'
        properties: {
          privateDnsZoneId: privateDnsZoneMonitor.id
        }
      }
      {
        name: 'oms'
        properties: {
          privateDnsZoneId: privateDnsZoneOms.id
        }
      }
      {
        name: 'ods'
        properties: {
          privateDnsZoneId: privateDnsZoneOds.id
        }
      }
      {
        name: 'agentsvc'
        properties: {
          privateDnsZoneId: privateDnsZoneAgentSvc.id
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
