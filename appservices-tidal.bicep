// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

// This template is used as a module from the main.bicep template. 
// The module contains a template to create network resources.
targetScope = 'resourceGroup'

param location string
param prefix string
param tags object

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Prefix to use for VM names')
param vmNamePrefix string = '${prefix}vm'

@description('Size of the virtual machines')
param vmSize string = 'Standard_D2as_v5'

@description('Loab Balancer name')
param loadBalancerName string = '${prefix}-ilb'

@description('Network Interface name')
param networkInterfaceName string = '${prefix}-nic'

@description('Availability Set name')
param availabilitySetName string = '${prefix}-AvSet'

@description('Storage Type for Vhds')
param storageAccountType string = 'Standard_LRS'

var storageAccountName = uniqueString(resourceGroup().id)
var numberOfInstances = 2

@description('VNet Name')
param vnetName string

@description('Subnet Name')
param subnetName string

resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  name: '${vnetName}/${subnetName}'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
}

resource availabilitySet 'Microsoft.Compute/availabilitySets@2021-11-01' = {
  name: availabilitySetName
  location: location
  tags: tags
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformUpdateDomainCount: 2
    platformFaultDomainCount: 2
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = [for i in range(0, numberOfInstances): {
  name: '${networkInterfaceName}${i}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: appServiceSubnet.id
          }
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'BackendPool1')
            }
          ]
        }
      }
    ]
  }
  dependsOn: [
    loadBalancer
  ]
}]

resource loadBalancer 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: loadBalancerName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        properties: {
          subnet: {
            id: appServiceSubnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
        name: 'LoadBalancerFrontend'
      }
    ]
    backendAddressPools: [
      {
        name: 'BackendPool1'
      }
    ]
    loadBalancingRules: [
      {
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadBalancerName, 'LoadBalancerFrontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'BackendPool1')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'lbprobe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 15
        }
        name: 'lbrule'
      }
    ]
    probes: [
      {
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
        name: 'lbprobe'
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = [for i in range(0, numberOfInstances): {
  name: '${vmNamePrefix}${i}'
  location: location
  tags: tags
  plan: {
    name: 'tidal_tools'
    publisher: 'tidal-migrations'
    product: 'tidal_tools'
  }
  properties: {
    availabilitySet: {
      id: availabilitySet.id
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${vmNamePrefix}${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: storageAccountType
        }
      }

      // This is a placeholder image reference. You should replace this with your desired image reference.
      imageReference: {
        publisher: 'tidal-migrations'
        offer: 'tidal_tools'
        sku: 'tidal_tools'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}]
