    # Author:   Joey Brakefield
    # Date:     2022-04-25
    # Resources Created: 
    #   Managed Service Fabric (SFC)
    #       Certs for Authentication to the Managed Service Cluster
    #       Storage Accounts for the logs for the SFC
    #       Log Analytics Workspace to collect metrics for the SFC
    #   Azure Key Vault (AKV)
    #   Virtual Network for Private Communication To/From the SFC
    #   Internal Load Balancer to Enable Private Communication To/From SFC
    #   Azure DevOps Connection Info for CI/CD Pipeline


# params
param (
    
    [Parameter(Mandatory, HelpMessage="Must Set an Azure Location.")]
    [ValidateNotNullOrEmpty()]
    [string]$location,
    
    [Parameter(Mandatory, HelpMessage="Must set 3 letter customer/designation name")]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(3,3)]
    [string]$customerName,                                  # Must be 3 character abbreviation

    [Parameter(HelpMessage="Specify an existing Log Analytics Workspace. A new one is created if not defined.")]
    [string]$lawWorkspaceName,
    [Parameter(HelpMessage="Specify the Resource Group for the existing Log Analytics Workspace. A new one is created if not defined.")]
    [string]$lawWorkspaceRg,

    [Parameter(Mandatory, HelpMessage="Specify the admin group's display name for the resources")]
    [ValidateNotNullOrEmpty()]
    [string]$adminGrp,
    [Parameter(Mandatory, HelpMessage="Specify resource environment: prd, dev, or tst")]
    [ValidateSet("prd","dev","tst")]                                # Must be 3 letters
    [ValidateLength(3,3)]
    [string]$environ = "tst",                                        # Must be 3 character abbreviation
    [Parameter(Mandatory, HelpMessage="Specify the management AKV where you have pfx-secret cert passphrase & clusteradmin password.")]
    [ValidateNotNullOrEmpty()]
    [string]$mgmtAkv,
    [Parameter(Mandatory, HelpMessage="Specify the AKV secret name that corresponds to clusteradmin username.")]
    [ValidateNotNullOrEmpty()]
    [string]$clusterAdminUsername                                                

)


if ((Get-AzResourceProvider -ProviderNamespace Microsoft.ServiceFabric -Location $location ).RegistrationState -eq "NotRegistered"){
    write-host "Azure Resource Provider for Service Fabric is not registered. Registering that now. `n Execute the script again in 10 minutes." -ForegroundColor Yellow -BackgroundColor DarkGray 
    Register-AzResourceProvider -ProviderNamespace Microsoft.ServiceFabric -ConsentToPermissions $true -Verbose
    Break
} else {
    Write-Host "Azure Resource Provider registered. Moving on..." -ForegroundColor Cyan
}
if ((Get-Host).Version.ToString() -notlike "5.*") {
    write-host "You MUST use Windows PowerShell (5.x) due to crytographic module issues in PowerShell Core (ver > 5.x)" -ForegroundColor Red -BackgroundColor Gray 
    Break
} else {
    Write-Host "PowerShell version is correct for crytographic dependencies. Moving on..." -ForegroundColor Cyan
}


# Azure Variables
$rg = "rg-$customerName-$environ"
$subId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id

## Mgmt Azure Variables (See README.md) <--- change as needed ############################
$certPassphraseAkvSecret = "pfx-secret"

# AKV Variables
$akvName = "akv-$customerName-$environ"
$adminGrpId = (get-azadgroup  -DisplayName $adminGrp).Id      # This group will be granted rights to control the new Azure Key Vault



# Managed Service Fabric Cluster Variables
$clusterName = "msf-"+$customerName+"-"+$environ+"-01"
$publicIp = (Invoke-WebRequest ifconfig.me/ip).Content.Trim() 
# $logStoAcct = "salog"+$customerName+$environ+$(get-random -Minimum 01 -Maximum 99)
# $appLogStoAcct = "saailog"+$customerName+$environ+$(get-random -Minimum 01 -Maximum 99)
$numClusterNodes = 3
$clusterSku = 'Basic'

if ($environ -eq 'prd'){
    $numClusterNodes = 5
    $clusterSku = "Standard"
}

# VNet Variables
$vnetAddressPrefix = "10.6.0.0/16"                                  # This can be changed to suit your IPAM needs. If not Class A -- 10.x.x.x, make sure to change the split command in the VNET section below 


# Cert Variables for AuthN to the Managed Service Fabric Cluster (SFC)
$fqdn = "$clusterName.$location.cloudapp.azure.com"



## Cert Variables config: this is the master password that we use to encrypt all of certificates. You can hardcode this if you'd like to use your own password. Make sure it's in "quotes" as a string
$Password = (Get-AzKeyVaultSecret -VaultName $mgmtAkv -Name $certPassphraseAkvSecret -AsPlainText)
$KeyVaultCertName = "$clusterName-cert"
$akvCertSecret = "$KeyVaultCertName-secret"
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$CertDir = "$HOME\certs"
$CertFileFullPath = "$certdir\$fqdn.pfx"

#___________________________________________________________________________________________
# Begin Resource Creation
#___________________________________________________________________________________________

# Create RG
if (!(Get-AzResourceGroup -Name $rg -Location $location -ErrorAction SilentlyContinue -WarningAction Ignore)) {
    New-AzResourceGroup -Name $rg -Location $location -Force
} else {
    Write-Host "Resource Group already present. Moving on..." -ForegroundColor Cyan
}

# Create Log Analytics Workspace (law)
if ([string]::IsNullOrEmpty($lawWorkspaceName) -or [string]::IsNullOrEmpty($lawWorkspaceRg)) {
    Write-Host "Log Analytics Workspace not defined. Creating or retrieving previously built one..." -ForegroundColor Cyan
    if (!(Get-AzOperationalInsightsWorkspace -Name "law-$customerName-$environ" -ResourceGroupName $rg -ErrorAction SilentlyContinue)) {
        $lawWorkspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $rg -Location $location -Sku pergb2018 -Name "law-$customerName-$environ" 
        $lawWorkspace.Name
        $lawWorkspaceId = $lawWorkspace.CustomerId
        
    } else {
        Write-Host 
        $lawWorkspace = Get-AzOperationalInsightsWorkspace -Name "law-$customerName-$environ" -ResourceGroupName $rg -ErrorAction Stop
        $lawWorkspace.Name
        
        
    }
    
    $lawWorkspaceKey = ($lawWorkspace | Get-AzOperationalInsightsWorkspaceSharedKeys -ErrorAction Stop).SecondarySharedKey 
    $lawWorkspaceId = $lawWorkspace.CustomerId
    $lawWorkspaceResId = $lawWorkspace.ResourceId
    

} else {
    write-host "Log Analytics Workspace exists. Moving on..." -ForegroundColor Cyan
    $lawWorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $lawWorkspaceRg -Name $lawWorkspaceName -ErrorAction Stop).CustomerId
    $lawWorkspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $lawWorkspaceRg -Name $lawWorkspaceName -ErrorAction Stop ).SecondarySharedKey
    $lawWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $lawWorkspaceRg -Name $lawWorkspaceName
    Write-Host "Existing LAWS customer ID is: $lawWorkspaceId"
}
 
# Create Virtual Network (VNET) 
if (!(Get-AzVirtualNetwork -ResourceGroupName $rg -Name "vnt-$customerName-sfc-$environ" -ErrorAction Ignore) ){
    $sfcSubnet = New-AzVirtualNetworkSubnetConfig -Name "snt-sfc-$environ-01" -AddressPrefix (($($vnetAddressPrefix -split "\.")[0..1] -join ".") + '.0.0/24')
    $client4SfcSubnet = New-AzVirtualNetworkSubnetConfig -Name "snt-sfc-clients-$environ-01" -AddressPrefix (($($vnetAddressPrefix -split "\.")[0..1] -join ".") + '.1.0/24')
    $vnet = New-AzVirtualNetwork -ResourceGroupName $rg -Name "vnt-$customerName-sfc-$environ" -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $sfcSubnet,$client4SfcSubnet
    Write-Host [$vnet.Name "has been created with the following subnets" $vnet.SubnetsText] -ForegroundColor Cyan
    Start-Sleep 30
} else {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $rg -Name "vnt-$customerName-sfc-$environ"
    $subs2write = ($vnet | Get-AzVirtualNetworkSubnetConfig | Select-Object Name, AddressPrefix)
    Write-Host "The VNET " $vnet.Name "already exists in "$vnet.ResourceGroupName -ForegroundColor Cyan
    $vnetOutput = ($vnet | Select-Object Name, @{label="Address Space";expression={$_.AddressSpace.AddressPrefixes}})
    Start-Sleep 5  
} 


## Ensure that the SFC can modify the networking of the VNET 
$sfcSPN = Get-AzADServicePrincipal -DisplayNameBeginsWith "Azure Service Fabric Resource Provider"
$vnetACLs = Get-AzRoleAssignment -Scope $vnet.Id

if ($vnetACLs.ObjectId -notcontains $sfcSPN.Id) {New-AzRoleAssignment -ObjectId $sfcSPN.Id -RoleDefinitionId "4d97b98b-1d4f-4787-a291-c67834d212e7" -Scope $vnet.Id
write-host "Added " $sfcSPN.DisplayName " to " $vnet.Name " inside " $vnet.ResourceGroupName -ForegroundColor Green
} else {
    write-host $sfcSPN.DisplayName "is already a Network Contributor on" $vnet.Name "in RG: " $vnet.ResourceGroupName -ForegroundColor Cyan
}
$subnetId = $vnet | Get-AzVirtualNetworkSubnetConfig -Name "snt-sfc-$environ-01"
Start-Sleep 15

# Create Azure Key Vault (AKV)
if (!(Get-AzKeyVault -VaultName $akvName)){
    Write-Host "Building Azure Key Vault..." -ForegroundColor Green
    $akvDeploy = New-AzResourceGroupDeployment -Name "akv-deploy" -ResourceGroupName $rg -Mode Incremental -TemplateFile .\akv\akv.bicep -akvName $akvName -location $location -subId $subId -tenantId $tenantId -admingrpId $adminGrpId -ErrorAction Stop
    Start-Sleep 30
    write-host $akvDeploy.ProvisioningState " at " $akvDeploy.Timestamp
    } else {
        $akvDeploy = Get-AzKeyVault -VaultName $akvName
        Write-Host "Azure Key Vault in Place. Moving on." -ForegroundColor Cyan}

    
## Ensure Admin Group Has Proper Rights
if ( (!(get-azroleassignment -ObjectId $adminGrpId -RoleDefinitionName "Key Vault Secrets Officer" -Scope (Get-AzKeyVault -VaultName $akvName).ResourceId)) -or 
    (!(get-azroleassignment -ObjectId $adminGrpId -RoleDefinitionName "Key Vault Certificates Officer" -Scope (Get-AzKeyVault -VaultName $akvName).ResourceId)))
    {
    Write-Host "Updating AKV Permissions..." -ForegroundColor Green 
    $akvDeploy = New-AzResourceGroupDeployment -Name "akv-deploy" -ResourceGroupName $rg -Mode Incremental -TemplateFile .\akv\akv.bicep -akvName $akvName -location $location -subId $subId -tenantId $tenantId -admingrpId $adminGrpId -ErrorAction Stop
    Start-Sleep 45
    } else { $akvDeploy = (Get-AzKeyVault -VaultName $akvName -ResourceGroupName $rg)
        Write-Host "Azure Key Vault permissions are correct. Moving on." -ForegroundColor Cyan}



# Create a New Self-Signed Certificate to Upload to AKV
Write-Host "Create self-signed cert for Service Fabric" -ForegroundColor Green

### Create Cert on Local PC; Then Import into Azure Key Vault
If(!(test-path $CertDir))
{
      New-Item -ItemType Directory -Force -Path $CertDir
} else {
    Write-Host "Cert Directory Exists. Moving On..." -ForegroundColor Cyan
}



if (!(test-path $CertFileFullPath) -and !(Get-AzKeyVaultCertificate -VaultName $akvName -Name $KeyVaultCertName) ) {  

    write-host "creating new certificate and depositing in Cert:\CurrentUser\My & \n" $CertFileFullPath "\n & " $akvName -ForegroundColor Cyan
    $NewCert = New-SelfSignedCertificate -CertStoreLocation Cert:\CurrentUser\My -DnsName $fqdn -KeyExportPolicy ExportableEncrypted


    Export-PfxCertificate -FilePath $CertFileFullPath -Cert $NewCert -Password $SecurePassword 

    $Bytes = [System.IO.File]::ReadAllBytes($CertFileFullPath)
    $Base64 = [System.Convert]::ToBase64String($Bytes)

    $JSONBlob = @{
        data = $Base64
        dataType = 'pfx'
        password = $Password
    } | ConvertTo-Json

    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)

    $SecretValue = ConvertTo-SecureString -String $Content -AsPlainText -Force
    $NewSecret = Set-AzKeyVaultSecret -VaultName $akvName -Name $akvCertSecret -SecretValue $SecretValue 

    Write-Host
    Write-Host "Source Vault Resource Id: "$(Get-AzKeyVault -VaultName $akvName).ResourceId
    Write-Host "Certificate Secret URL : "$NewSecret.Id
    Write-Host "Certificate Thumbprint : "$NewCert.Thumbprint

    $akvcert = Import-AzKeyVaultCertificate -VaultName $akvName -Name $KeyVaultCertName -Password $SecurePassword -FilePath $CertFileFullPath
    Write-Host "Certificate Uploaded to :"$akvcert.VaultName " as "$akvcert.Name


    $thumb = $NewCert.Thumbprint



    } elseif ((!(test-path $CertFileFullPath)) -and (Get-AzKeyVaultCertificate -VaultName $akvName -Name $KeyVaultCertName -ErrorAction SilentlyContinue)) {
        if (Get-ChildItem Cert:\CurrentUser\my\ | Where-Object {$_.Subject -eq "CN=$fqdn"}) {
            write-host "deleting old cert in certificate store and replacing it with AKV cert. " -ForegroundColor Cyan
            (Get-ChildItem Cert:\CurrentUser\my\ | Where-Object {$_.Subject -eq "CN=$fqdn"}) | remove-item -Force -Verbose
        }
    
    write-host $CertFileFullPath " is missing but AKV cert present. Creating local copy from AKV to connect to SF cluster."
    $cert = Get-AzKeyVaultCertificate -VaultName $akvName -Name $KeyVaultCertName
    $secret = Get-AzKeyVaultSecret -VaultName $akvName -Name $cert.Name
    $secretValueText = '';
    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
    try {
            $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
        } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
        }
    $secretByte = [Convert]::FromBase64String($secretValueText)
    $x509Cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2
    $x509Cert.Import($secretByte, "", "Exportable,PersistKeySet")
    $type = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx
    $pfxFileByte = $x509Cert.Export($type, $password)
    
    ### Write to a File on Local Filesystem
    [System.IO.File]::WriteAllBytes($CertFileFullPath, $pfxFileByte)
    $thumb = $cert.Thumbprint

    ### Import to Local PC Cert Store
    if (!(Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.subject -eq "CN=$fqdn"}) ) {
        Import-PfxCertificate -Password $SecurePassword -Exportable -CertStoreLocation Cert:\CurrentUser\My\ -FilePath $CertFileFullPath
    }
    $thumb = (Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.subject -eq "CN=$fqdn"}).Thumbprint
    
    
    }  elseif ((test-path $CertFileFullPath) -and !(Get-AzKeyVaultCertificate -VaultName $akvName -Name $KeyVaultCertName -ErrorAction SilentlyContinue) ) {
        $akvName
        $CertFileFullPath
        $clusterName
        $akvcert = Import-AzKeyVaultCertificate -VaultName $akvName -Name $KeyVaultCertName -Password $SecurePassword -FilePath $CertFileFullPath -ErrorAction Stop
        Write-Host "Certificate Uploaded to :"$akvcert.VaultName " as "$akvcert.Name
        $thumb = (Get-AzKeyVaultCertificate -VaultName $akvName -Name $clusterName-cert).Thumbprint 
    } else {
        Write-Host "Both local cert store and AKV are present for AuthN. Now getting the certificate thumbprint for SF deployment authentication..." -ForegroundColor Cyan
        $thumb = (Get-AzKeyVaultCertificate -VaultName $akvName -Name $clusterName-cert).Thumbprint
    }  


### End certificate management/creation....
# Service Fabric Cluster Deployment
Write-Host "Service Fabric update/initiation deployment commencing..." -ForegroundColor Green
# write-host "Checking to see if storage accounts already exist that are attached to an existing SFC..."





Write-Host "Checking for Cluster Administrator Password..."
if (Get-AzKeyVaultSecret -VaultName $mgmtAkv -Name $clusterAdminUsername) {
    $clusterAdminPassword = (Get-AzKeyVaultSecret -VaultName $mgmtAkv -Name $clusterAdminUsername).SecretValue
    Write-Host "Retrieved Cluster Admin Password from " $mgmtAkv ". Moving on..." -ForegroundColor Cyan
    $clusterAdminPasswordOutput = "Retrieved Cluster Admin Password from" +$mgmtAkv 
} else {
    $chars = "abcdefghijkmnopqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ23456789!#%&?".ToCharArray()
    $clusterAdminPassword = ""
    1..10 | ForEach-Object {  $clusterAdminPassword += $chars | Get-Random }
    $clusterAdminPassword | ConvertTo-SecureString
    $clusterAdminPasswordOutput = $clusterAdminPassword
    Write-Host "Created Cluster Admin and deposited secret into " $akvName " as " $clusterAdminUsername". Moving on..." -ForegroundColor Cyan
} 

ConvertFrom-SecureString $clusterAdminPassword

# We're going to connect to the cluster we will build out. First, we'll check to see if you have the SFC module installed. Then install it if not.
if (!(Get-Module Az.ServiceFabric)){
    if (!(Get-PackageProvider -Name NuGet)) {
        Install-PackageProvider -Name NuGet -Force
    }
    Install-Module Az.ServiceFabric -Force
} else {
    Import-Module Az.ServiceFabric 
}

write-host "thumbprint is: " $thumb
if (!(Get-AzServiceFabricManagedCluster -ResourceGroupName $rg -Name $clusterName -ErrorAction SilentlyContinue))  {
    Write-Host "New-New Service Fabric Deployment Commencing..."
    $sfDeploy = New-AzResourceGroupDeployment -Name "sf-$clusterName-deploy" -Mode Incremental -ResourceGroupName $rg `
    -TemplateFile  ".\sf\sfmanaged.bicep" `
    -thumb $thumb  `
    -env $environ `
    -subnetId $subnetId.Id `
    -customerName $customerName `
    -location $location `
    -lawWorkspaceId $lawWorkspaceId `
    -lawWorkspaceKey $lawWorkspaceKey `
    -clusterName $clusterName `
    -publicIp $publicIp `
    -adminUserName $clusterAdminUsername `
    -adminPassword $clusterAdminPassword `
    -subscriptionSFRPId $sfcSPN.Id `
    -lawWorkspaceResId $lawWorkspaceResId `
    -clusterSku $clusterSku `
    -numClusterNodes $numClusterNodes `
    -ErrorAction Stop `
    -Verbose # -logStoAcct $logStoAcct -appLogStoAcct $appLogStoAcct -subId $subId for later impl.

    write-host $sfDeploy.ProvisioningState " at " $sfDeploy.Timestamp
} elseif ((Get-AzResourceGroupDeployment  -ResourceGroupName $rg -Name "sf-$clusterName-deploy").ProvisioningState -ne "Succeeded")  {
    Write-Host "Previously failed Managed Service Fabric attempt detected. Redeploying..."
    $sfDeploy = New-AzResourceGroupDeployment -Name "sf-$clusterName-deploy" -Mode Incremental -ResourceGroupName $rg `
    -TemplateFile  ".\sf\sfmanaged.bicep" `
    -thumb $thumb  `
    -env $environ `
    -subnetId $subnetId.Id `
    -customerName $customerName `
    -location $location `
    -lawWorkspaceId $lawWorkspaceId `
    -lawWorkspaceKey $lawWorkspaceKey `
    -clusterName $clusterName `
    -publicIp $publicIp `
    -adminUserName $clusterAdminUsername `
    -adminPassword $clusterAdminPassword `
    -subscriptionSFRPId $sfcSPN.Id `
    -lawWorkspaceResId $lawWorkspace.ResourceId `
    -clusterSku $clusterSku `
    -numClusterNodes $numClusterNodes `
    -ErrorAction Stop `
    -Verbose
} else {
    $sfDeploy = (Get-AzResourceGroupDeployment  -ResourceGroupName $rg -Name "sf-$clusterName-deploy")
}




## Collect Node Type Name to ID the underlying SFC VMSS Machines
$ntName = $customerName+$environ+"NT1"
$mgdSfcClusterRg = Get-AzVmss -Name $ntName

# Create Internal Load Balancer for Private Comms to VNET


$privIPAddress = ($($vnetAddressPrefix -split "\.")[0..2] -join ".") + ".101"

if ($sfDeploy.ProvisioningState -ne "Succeeded")  { Write-Host "Service Fabric Failed. Skipping Internal Load Balancer Deployment and Breaking out of Script" -ForegroundColor Red -BackgroundColor Gray
        Break
} elseif (!(get-azloadbalancer -ResourceGroupName $rg -Name "ilb-$customerName-$environ" -ErrorAction SilentlyContinue) -or !(get-azloadbalancer -ResourceGroupName $rg -Name "ilb-$customerName-$environ" -ErrorAction SilentlyContinue).LoadBalancingRules) {
    Write-Host "Now Deploying Internal Load Balancer for Managed Service Fabric VMSS to communicate out to Mongo" -ForegroundColor Green
    $ilbDeploy = New-AzResourceGroupDeployment -Name "ilb-$clusterName-deploy" -Mode Incremental -ResourceGroupName $rg -TemplateFile ".\ilb\ilb.bicep" -subnetId $subnetId.Id -customerName $customerName -location $location -env $environ -privIPAddress $privIPAddress -subId $subId -mgdSfcClusterRg $mgdSfcClusterRg.ResourceGroupName -ntName $ntName -clusterName $clusterName -dataDiskStoSku (Get-AzServiceFabricManagedNodeType -ClusterName (Get-AzServiceFabricManagedCluster -ResourceGroupName $rg).DnsName -ResourceGroupName $rg).DataDiskType -ErrorAction Stop

    Write-Host $ilbDeploy.Outputs.Keys $ilbDeploy.ProvisioningState "at" $ilbDeploy.Timestamp -ForegroundColor Green
} else {
    Write-Host "Internal Load Balancer in place and configured"
    $ilbDeploy = (Get-AzResourceGroupDeployment -ResourceGroupName $rg -Name "ilb-$clusterName-deploy")
}



### Deployment Outputs

write-host "Here are the deployment details for the environment: `n __________________________________________________________________" -ForegroundColor Cyan -BackgroundColor DarkBlue
Write-Host "`n"
write-host "For the VNET and subnets: " -ForegroundColor Green -BackgroundColor DarkBlue
write-host $vnetOutput

$subs2write.ForEach({write-host `n $_.name `n, $_.AddressPrefix `n})

Write-Host "`n"
write-host "For the Azure Key Vault:  " -ForegroundColor Green -BackgroundColor DarkBlue
$akvDeploy
Write-Host "`n"


write-host "For the Log Analytics Workspace:  " -ForegroundColor Green -BackgroundColor DarkBlue
write-host $lawWorkspace.Name "in" $lawWorkspace.ResourceGroupName
Write-Host "`n"
write-host "For the managed service fabric cluster: " -ForegroundColor Green -BackgroundColor DarkBlue
$sfDeploy
Write-Host "`n"
write-host "For the internal private load balancer for private resource connection to the service fabric cluster: `n" -ForegroundColor Green -BackgroundColor DarkBlue
$ilbDeploy
Write-Host "`n"
Write-Host "`n"
Write-Host "`n"
### Connection Details 
Write-Host "Connection Details `n ________________________________________________________________________________________________"

Write-Host "Input the .pfx password from the management Azure Key Vault to import the .pfx certificate manually "  -ForegroundColor Cyan
$certPassphrase = (Get-AzKeyVaultSecret -VaultName $mgmtAkv -Name $certPassphraseAkvSecret -AsPlainText)
write-host $certPassphrase -ForegroundColor Green -BackgroundColor DarkYellow



# Write out Az DevOps connection info
Write-Host "Input the following into the Server Certificate Thumbprint(s) text box on your Azure DevOps service connection -->  `n"-ForegroundColor Green 




[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$CertFileFullPath"))
$resourceId = (Get-AzServiceFabricManagedCluster -ResourceGroupName $rg).Id
$cluster = Get-AzResource -ResourceId $resourceId -ApiVersion 2021-01-01
$serverCertThumbprints = $cluster.Properties.clusterCertificateThumbprints
$clusterEndpoint = $cluster.Properties.fqdn + ":" + $cluster.Properties.clientConnectionPort
#Connect using first client certificate, specified by its thumbprint. The client certificate is installed in CurrentUser\My store on the local computer.


$clientCertThumbprints = $cluster.Properties.clients
Write-Host "`n"
Write-Host "`n"
Write-Host "`n"

foreach ($clientCertThumbprint in $clientCertThumbprints) {
try {
    Write-Host "Connecting to $clusterEndpoint with client certificate $clientCertThumbprint .." -ForegroundColor Cyan

    Connect-ServiceFabricCluster -ConnectionEndpoint $clusterEndpoint -ServerCertThumbprint $serverCertThumbprints -X509Credential -FindType FindByThumbprint -FindValue $clientCertThumbprint.Thumbprint -StoreLocation CurrentUser -StoreName My

    Write-Host "`n `n You have successfully connected to your new or updated Managed Service Fabric cluster!" -ForegroundColor Green -BackgroundColor DarkBlue

    } catch {
        Write-Host "Could not connect to the cluster." -ForegroundColor Red
    }
}




Write-Host $clusterAdminPasswordOutput -ForegroundColor 'Yellow'
