param customerName string 
param location string 
param env string 
param privIpAddress string 
param subId string 
param mgdSfcClusterRg string 
param ntName string 
param subnetId string 
param clusterName string 
param dataDiskStoSku string 

@allowed([
  'Standard'
  'Basic'
])
param ilbSku string = 'Basic'

// @allowed([
//   'Global'
//   'Regional'
//   'null'
// ])
param ilbTier string = 'Regional'

var ilbName = 'ilb-${customerName}-${env}'




resource ilb4MgdSFC 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: ilbName
  location: location
  tags: {}
  sku: {
    name: ilbSku
    tier: ilbTier
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'ife-${customerName}-${env}'
        properties: {
          privateIPAddress: privIpAddress
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: '/subscriptions/${subId}/resourceGroups/rg-${customerName}-${env}/providers/Microsoft.Network/virtualNetworks/vnt-${customerName}-sfc-${env}/subnets/snt-sfc-${env}-01'
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'ibe-${customerName}-${env}-vmss4sfc'
      }
    ]
   
    loadBalancingRules: [
      {
        name: 'ibr-${customerName}-${env}-8168'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', ilbName, 'ife-${customerName}-${env}')

            //id: '/subscriptions/${subId}/resourceGroups/rg-${customerName}-${env}/providers/Microsoft.Network/loadBalancers/ilb-${customerName}-${env}/frontendIPConfigurations/ife-${customerName}-${env}'
          }
          frontendPort: 8168
          backendPort: 8168
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          protocol: 'Tcp'
          loadDistribution: 'Default'
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', ilbName, 'ihp-${customerName}-${env}-8168')
            //id: '/subscriptions/${subId}/resourceGroups/rg-${customerName}-${env}/providers/Microsoft.Network/loadBalancers/ilb-${customerName}-${env}/probes/ihp-${customerName}-${env}-8168'
          }
          disableOutboundSnat: true
          enableTcpReset: false
          backendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', ilbName, 'ibe-${customerName}-${env}-vmss4sfc')
              //id: '/subscriptions/${subId}/resourceGroups/rg-${customerName}-${env}/providers/Microsoft.Network/loadBalancers/ilb-${customerName}-${env}/backendAddressPools/ibe-${customerName}-${env}'
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'ihp-${customerName}-${env}-8168'
        properties: {
          protocol: 'Tcp'
          port: 8168
          requestPath: null
          intervalInSeconds: 30
          numberOfProbes: 2
        }
      }
    ]
    inboundNatRules: []
    outboundRules: []
  }
  dependsOn: []
}

module vmssUpdate4SFC './/nested_VmssUpdate.bicep' = {
  name: 'VMSSUpdate4ILB'
  scope: resourceGroup('${mgdSfcClusterRg}')
  params: {
    ntName: ntName
    location: location
    subId: subId
    ilbName: ilb4MgdSFC.name
    customerName: customerName
    subnetId: subnetId
    mgdSfcClusterRg: mgdSfcClusterRg
    env: env
    clusterName: clusterName
    dataDiskStoSku: dataDiskStoSku
  }

}


output ilbRg string = ilb4MgdSFC.id
