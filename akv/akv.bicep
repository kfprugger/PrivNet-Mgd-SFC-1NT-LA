param akvName string = 'rjb-pai-test'
param location string = 'eastus'
param adminGrpId string
param subId string
param tenantId string
var roleIdPrefix = '/subscriptions/${subId}/providers/Microsoft.Authorization/roleDefinitions'


resource sfcAkv 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: akvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enabledForDeployment: true
    enabledForTemplateDeployment: true
  }
  
}


// 
resource akvSecretsAdmin 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('Key Vault Secrets Officer', akvName, subscription().subscriptionId )
  scope: sfcAkv
  properties: {
    principalId: adminGrpId
    roleDefinitionId: '${roleIdPrefix}/b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // AKV Secrets Officer 
  }
}

resource akvCertsAdmin 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('Key Vault Certificates Officer', akvName, subscription().subscriptionId )
  scope: sfcAkv
  properties: {
    principalId: adminGrpId
    roleDefinitionId: '${roleIdPrefix}/a4417e6f-fecd-4de8-b567-7b0420556985' // AKV Secrets Officer 
  }
}

