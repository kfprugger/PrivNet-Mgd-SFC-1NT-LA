// Azure Config
param lawWorkspaceId string 
param lawWorkspaceResId string 
param subscriptionSFRPId string
@description('Key for monitoring agents on the Agents Management blade')
param lawWorkspaceKey string 

@description('Remote desktop user password. Must be a strong password')
@secure()
param adminPassword string 

param adminUserName string 
param userAssignedIdentity string = 'uai-msfc-id'
@description('https://docs.microsoft.com/azure/role-based-access-control/role-definitions-list \'Managed Identity Operator\' read and assign')
param roleDefinitionId string = 'f1a07417-d97a-45cb-824c-7a7467783830' // Managed Identity Operator

@description('generate guid one time and reuse for same assignment: [guid]::NewGuid() ')
param roleAssignmentId string = newGuid()

// Env Variables
param customerName string 
param env string
param location string

// Cluster Config
param thumbprint string 
param clusterName string 
param clusterSku string 
param publicIp string  


  // NodeType Config
  var ntName = '${customerName}${env}NT1'
  param numClusterNodes int = 3
  param dataDiskStoSku string = 'Premium_LRS'
  param dataDiskSizeGB int = 64
  param dataDiskLetter string = 'S'


// Storage account 
param logStoAcct string = 'sa${customerName}logsto${env}01'
// param appLogStoAcct string = 'sa${customerName}applog${env}01'
param stoSkuName string = 'Standard_LRS'
param stoKind string     = 'StorageV2'

// Virtual Network Config
param subnetId string  


// Begin Storage Creation 

resource LogStorageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: logStoAcct
  location: location
  sku: {
    name: stoSkuName
  }
  kind: stoKind 
  tags: {
    resourceType: 'Service Fabric'
    clusterName: clusterName
  }
}


// resource applicationDiagnosticsStorageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
//   name: appLogStoAcct
//   location: location
//   sku: {
//     name: stoSkuName
//   }
//   kind: stoKind
//   tags: {
//     resourceType: 'Service Fabric'
//     clusterName: clusterName
//   }
// }


// Being App Insights Creation for Log Sink Creation
resource appInsights4SFC 'Microsoft.Insights/components@2020-02-02' = {
  name: 'aai-${clusterName}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
  
}

// Begin User-Assigned Identity Creation & Assignment 
resource userAssignedIdentity4SFC 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userAssignedIdentity
  location: location
}

resource roleAssignmentID_resource 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: userAssignedIdentity4SFC
  name: roleAssignmentId
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${roleDefinitionId}'
    principalId: subscriptionSFRPId
  }
}



// // Begin Event Hub for Sink Creation
// resource eh4SFC 'Microsoft.EventHub/namespaces@2021-11-01' = {
//   name: 'ehb-${clusterName}'
//   location: location
//   sku: {
//     name: 'Basic'
//     tier: 'Basic'
//   }
// }


// Begin Cluster Creation

resource paicluster 'Microsoft.ServiceFabric/managedClusters@2022-01-01' = {
  // dependsOn: [
  //   LogStorageAccount
  //   applicationDiagnosticsStorageAccount
  // ]
  name: clusterName
  location: location
  sku: {
    name: clusterSku
  }
  properties: {
    clusterUpgradeMode: 'Automatic'
    clusterUpgradeCadence: 'Wave0'
    enableAutoOSUpgrade: true

    //zonalResiliency: true
    addonFeatures: [
      'DnsService'
    ]
    subnetId: subnetId
    loadBalancingRules: [
      {
        backendPort: 8168
        frontendPort: 8168
        probePort: 8168
        probeProtocol: 'tcp'
        protocol: 'tcp'
        
      }
    ]
    networkSecurityRules: [
        {
        name: 'ApiPinHole'
        protocol: 'tcp'
        sourcePortRange: '*'
        sourceAddressPrefix: '10.0.0.0/8'
        destinationAddressPrefix: '*'
        destinationPortRange: '8168'
        priority: 1000
        direction: 'inbound'
        access: 'allow'
        }
        // {
        // name: 'rdpInbound'
        // protocol: 'tcp'
        // sourcePortRange: '*'
        // sourceAddressPrefix: 'Internet'
        // destinationAddressPrefix: '*'
        // destinationPortRange: '3389-4500'
        // priority: 1001
        // direction: 'inbound'
        // access: 'allow'
        //   }
        {
          name: 'userPublicIP'
          protocol: 'tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: publicIp
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          priority: 1002
          direction: 'inbound'
          access: 'allow'
          }

      ]

    adminUserName: adminUserName
    adminPassword: adminPassword
    dnsName: clusterName
    
    clientConnectionPort: 19000
    
    httpGatewayConnectionPort: 19080

    clients: [
      {
        isAdmin: true
        thumbprint: thumbprint
      }
    ]
  }
}



// Continuing Cluster Config --> Node Type definition
resource paicluster_NT1 'Microsoft.ServiceFabric/managedClusters/nodeTypes@2022-01-01' = {
  // dependsOn: [
  //   LogStorageAccount
  //   applicationDiagnosticsStorageAccount
  // ]
  parent: paicluster
  name: ntName
  properties: {
    isPrimary: true
    vmImagePublisher: 'MicrosoftWindowsServer'
    vmImageOffer: 'WindowsServer'
    vmImageSku: '2019-Datacenter-with-Containers'
    vmImageVersion: 'latest'
    vmSize: 'Standard_D2s_v4' // <change to fit size requirements. Make sure the "s" is in the SKU name to support Premium SSDs.>
    vmInstanceCount: numClusterNodes
    vmManagedIdentity: {
      userAssignedIdentities: [
        userAssignedIdentity4SFC.id
      ]
    }
    dataDiskSizeGB: dataDiskSizeGB
    dataDiskType:dataDiskStoSku
    dataDiskLetter: dataDiskLetter
    placementProperties: {}
    
    capacities: {}
    vmExtensions: [
      {
        name: 'OMSExtension-${ntName}'
        properties: {
          publisher: 'Microsoft.EnterpriseCloud.Monitoring'
          type: 'MicrosoftMonitoringAgent'
          typeHandlerVersion: '1.0'
          autoUpgradeMinorVersion: true
          settings: {
            workspaceId: lawWorkspaceId
          }
          protectedSettings: {
            workspaceKey: lawWorkspaceKey
          }
        
        }
        
      }
      {
        name: 'VMDiagnosticsVmExt-${ntName}'
        properties: {
          type: 'IaaSDiagnostics'
          autoUpgradeMinorVersion: true
          protectedSettings: {
            storageAccountName: LogStorageAccount.name
            storageAccountKey: listKeys(LogStorageAccount.id, '2015-05-01-preview').key1
            storageAccountEndPoint: 'https://core.windows.net/'
          }
          publisher: 'Microsoft.Azure.Diagnostics'
          settings: {
            WadCfg: {
              DiagnosticMonitorConfiguration: {
                overallQuotaInMB: '50000'
                PerformanceCounters: {
                  scheduledTransferPeriod: 'PT1M'
                  sinks: 'AzMonSink'
                  PerformanceCounterConfiguration: [
                    {
                      counterSpecifier: '\\LogicalDisk(C:)\\% Free Space'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\LogicalDisk(${dataDiskLetter}:)\\% Free Space'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Memory\\Available MBytes'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Memory\\Pages/sec'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Paging File(_Total)\\% Usage'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\PhysicalDisk(C:)\\Current Disk Queue Length'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\PhysicalDisk(${dataDiskLetter}:)\\Current Disk Queue Length'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Process(_Total)\\Handle Count'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Process(_Total)\\Private Bytes'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Process(_Total)\\Thread Count'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\Processor(_Total)\\% Processor Time'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\TCPv4\\Connections Established'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\TCPv4\\Segments Received/sec'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\TCPv4\\Segments Retransmitted/sec'
                      sampleRate: 'PT10S'
                    }
                    {
                      counterSpecifier: '\\TCPv4\\Segments Sent/sec'
                      sampleRate: 'PT10S'
                    }
                  ]
                }
                EtwProviders: {
                  EtwEventSourceProviderConfiguration: [
                    {
                      provider: 'Microsoft-ServiceFabric-Actors'
                      scheduledTransferKeywordFilter: '1'
                      scheduledTransferPeriod: 'PT5M'
                      DefaultEvents: {
                        eventDestination: 'ServiceFabricReliableActorEventTable'
                      }
                    }
                    {
                      provider: 'Microsoft-ServiceFabric-Services'
                      scheduledTransferPeriod: 'PT5M'
                      DefaultEvents: {
                        eventDestination: 'ServiceFabricReliableServiceEventTable'
                      }
                    }
                  ]
                  EtwManifestProviderConfiguration: [
                    {
                      provider: 'cbd93bc2-71e5-4566-b3a7-595d8eeca6e8'
                      scheduledTransferLogLevelFilter: 'Information'
                      scheduledTransferKeywordFilter: '4611686018427387904'
                      scheduledTransferPeriod: 'PT5M'
                      DefaultEvents: {
                        eventDestination: 'ServiceFabricSystemEventTable'
                      }
                    }
                    {
                      provider: '02d06793-efeb-48c8-8f7f-09713309a810'
                      scheduledTransferLogLevelFilter: 'Information'
                      scheduledTransferKeywordFilter: '4611686018427387904'
                      scheduledTransferPeriod: 'PT5M'
                      DefaultEvents: {
                        eventDestination: 'ServiceFabricSystemEventTable'
                      }
                    }
                  ]
                }
                WindowsEventLog: {
                  scheduledTransferPeriod: 'PT5M'
                  DataSource: [
                    {
                      name: 'System!*[System[Provider[@Name=\'Microsoft Antimalware\']]]'
                    }
                    {
                      name: 'System!*[System[Provider[@Name=\'NTFS\'] and (EventID=55)]]'
                    }
                    {
                      name: 'System!*[System[Provider[@Name=\'disk\'] and (EventID=7 or EventID=52 or EventID=55)]]'
                    }
                    {
                      name: 'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
                    }
                    {
                      name: 'Microsoft-ServiceFabric/Admin!*[System[(Level=1 or Level=2 or Level=3)]]'
                    }
                    {
                      name: 'Microsoft-ServiceFabric/Audit!*[System[(Level=1 or Level=2 or Level=3)]]'
                    }
                    {
                      name: 'Microsoft-ServiceFabric/Operational!*[System[(Level=1 or Level=2 or Level=3)w]]'
                    }
                  ]
                }
              }
              SinksConfig: {
                Sink: [
                  {
                    name: 'AzMonSink'
                    AzureMonitor: {
                      resourceId: lawWorkspaceResId
                    }
                  }
                  {
                    name: 'ApplicationInsights'
                    ApplicationInsights: appInsights4SFC.properties.InstrumentationKey
                  }
                  // {
                  //   name: 'EventHub'
                  //   EventHub: {
                  //     Url: eh4SFC.properties.serviceBusEndpoint // 'https://myeventhub-ns.servicebus.windows.net/diageventhub'
                  //     SharedAccessKeyName: 'SendRule'
                  //     usePublisherId: false
                  //   }
                  // }
                ]
              }
            }
          }
          typeHandlerVersion: '1.5'
        }
      }
    ]

    }
}

