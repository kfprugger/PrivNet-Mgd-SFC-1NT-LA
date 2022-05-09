param ntName string
param location string
param subId string
param ilbName string
param customerName string = 'pai'
param subnetId string
param mgdSfcClusterRg string
param env string
param clusterName string

// var adminUsername ='${customerName}azureadmin'
// param computerNamePrefix string = 'pai'
// param dataDiskStoSku string

resource patstNT1 'Microsoft.Compute/virtualMachineScaleSets@2020-12-01' = {
  name: ntName
  location: location
  properties: {
    singlePlacementGroup: true
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      // osProfile: {
      //   computerNamePrefix: computerNamePrefix
      //   adminUsername: adminUsername
      //   windowsConfiguration: {
      //     provisionVMAgent: true
      //     enableAutomaticUpdates: false
      //   }
      //   secrets: []
      //   allowExtensionOperations: true
      //   requireGuestProvisionSignal: true
      // }
      // storageProfile: {
      //   osDisk: {
      //     osType: 'Windows'
      //     createOption: 'FromImage'
      //     caching: 'ReadOnly'
      //     managedDisk: {
      //       storageAccountType: 'Standard_LRS'
      //     }
      //     diskSizeGB: 127
      //   }
      //   dataDisks: [
      //     {
      //       lun: 0
      //       createOption: 'Empty'
      //       caching: 'None'
      //       managedDisk: {
      //         storageAccountType: dataDiskStoSku
      //       }
      //       diskSizeGB: 64
      //     }
      //   ]
      // }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${ntName}-NIC'
            properties: {
              primary: true
              enableAcceleratedNetworking: false
              dnsSettings: {
                dnsServers: []
              }
              enableIPForwarding: false
              ipConfigurations: [
                {
                  name: '${ntName}-IP'
                  properties: {
                    subnet: {
                      id: subnetId
                    }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      {
                        id: '/subscriptions/${subId}/resourceGroups/${mgdSfcClusterRg}/providers/Microsoft.Network/loadBalancers/LB-${clusterName}/backendAddressPools/LoadBalancerBEAddressPool'
                      }
                      {
                        id: '/subscriptions/${subId}/resourcegroups/rg-${customerName}-${env}/providers/Microsoft.Network/loadBalancers/${ilbName}/backendAddressPools/ibe-${customerName}-${env}-vmss4sfc'
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        id: '/subscriptions/${subId}/resourceGroups/${mgdSfcClusterRg}/providers/Microsoft.Network/loadBalancers/LB-${clusterName}/inboundNatPools/LBBackendNatPool${ntName}'
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      // extensionProfile: {
      //   extensions: [
      //     {
      //       name: 'ServiceFabricMCNodeVmExt'
      //       properties: {
      //         autoUpgradeMinorVersion: false
      //         provisionAfterExtensions: []
      //         publisher: 'Microsoft.Azure.ServiceFabric.MC'
      //         type: 'ServiceFabricMCNode'
      //         typeHandlerVersion: '0.7'
      //         settings: {
      //           ProtectedSettingsEncrypted: true
      //           IncludeUserEvents: false
      //           SfDriveLetter: 'S'
      //           UseTempDataDisk: false
      //           AdditionalDataDisks: null
      //         }
      //       }
      //     }
      //     {
      //       name: 'AzureMonitorWindowsAgent-NT1'
      //       properties: {
      //         autoUpgradeMinorVersion: true
      //         provisionAfterExtensions: [
      //           'ServiceFabricMCNodeVmExt'
      //         ]
      //         publisher: 'Microsoft.Azure.Monitor'
      //         type: 'AzureMonitorWindowsAgent'
      //         typeHandlerVersion: '1.2'
      //         settings: {
      //           workspaceId: 'de64aba3-a5b7-4fee-8da9-b70e10c47489'
      //         }
      //       }
      //     }
      //   ]
      // }
    }
    // provisioningState: 'Succeeded'
    // overprovision: false
    // doNotRunExtensionsOnOverprovisionedVMs: false
    // uniqueId: '58c3378f-f2af-4363-8f52-24ae50716e44'
    // platformFaultDomainCount: 5
  }
  tags: {}
}
