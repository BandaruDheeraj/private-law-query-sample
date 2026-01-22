@description('Location for the VMs')
param location string

@description('Name of the VNet')
param vnetName string

@description('Name of the workload subnet')
param subnetName string

@description('Resource ID of the Log Analytics Workspace')
param workspaceId string

@description('Tags to apply to resources')
param tags object = {}

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs - provide a secure password or use the generated default')
@secure()
param adminPassword string = 'P@ss${uniqueString(newGuid())}w0rd!'

var vmConfigs = [
  {
    name: 'app-vm'
    size: 'Standard_B2s'
  }
  {
    name: 'db-vm'
    size: 'Standard_B2s'
  }
  {
    name: 'web-vm'
    size: 'Standard_B2s'
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: subnetName
}

// Network interfaces (no public IPs - private only)
resource nics 'Microsoft.Network/networkInterfaces@2023-05-01' = [for vm in vmConfigs: {
  name: 'nic-${vm.name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
  }
}]

// Virtual Machines
resource vms 'Microsoft.Compute/virtualMachines@2023-07-01' = [for (vm, i) in vmConfigs: {
  name: vm.name
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vm.size
    }
    osProfile: {
      computerName: vm.name
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
        }
      ]
    }
  }
}]

// Azure Monitor Agent extension
resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2023-07-01' = [for (vm, i) in vmConfigs: {
  parent: vms[i]
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}]

// Data Collection Rule for Syslog and Performance
resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-workload-vms'
  location: location
  tags: tags
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'syslog'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'daemon'
            'kern'
            'syslog'
            'user'
            'local0'
            'local1'
            'local2'
            'local3'
            'local4'
            'local5'
            'local6'
            'local7'
          ]
          logLevels: [
            'Debug'
            'Info'
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
      ]
      performanceCounters: [
        {
          name: 'perfCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            'Processor(*)\\% Processor Time'
            'Memory(*)\\% Used Memory'
            'LogicalDisk(*)\\% Free Space'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'la-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Syslog'
          'Microsoft-Perf'
        ]
        destinations: [
          'la-destination'
        ]
      }
    ]
  }
}

// Associate VMs with the DCR
resource dcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = [for (vm, i) in vmConfigs: {
  name: 'dcr-assoc-${vm.name}'
  scope: vms[i]
  properties: {
    dataCollectionRuleId: dcr.id
  }
}]

output vmNames array = [for vm in vmConfigs: vm.name]
output dcrId string = dcr.id
