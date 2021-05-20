$rg = @{
    Name = 'wizz-ngen-ps-rg'
    Location = 'WestEurope'
}
New-AzResourceGRoup @rg

# Creating an inbound network security group rule for port 22
$nsgRuleExternalSSH = New-AzNetworkSecurityRuleConfig `
-Name "externalSSHRule"  `
-Protocol "Tcp" `
-Direction "Inbound" `
-Priority 1000 `
-SourceAddressPrefix * `
-SourcePortRange * `
-DestinationAddressPrefix $servicePip.IpAddress[0] `
-DestinationPortRange 22 `
-Access "Allow"

$nsgRuleInternalSSH = New-AzNetworkSecurityRuleConfig `
-Name "internalSSHRule"  `
-Protocol "Tcp" `
-Direction "Inbound" `
-Priority 1001 `
-SourceAddressPrefix $servicePip.IpAddress[0] `
-SourcePortRange 22 `
-DestinationAddressPrefix $webPip.IpAddress[0]`
-DestinationPortRange 22 `
-Access "Allow"

# Creating an inbound network security group rule for port 80
$nsgRuleWeb = New-AzNetworkSecurityRuleConfig `
  -Name "inboundWebRule"  `
  -Protocol "Tcp" `
  -Direction "Inbound" `
  -Priority 1002 `
  -SourceAddressPrefix * `
  -SourcePortRange * `
  -DestinationAddressPrefix $webPip.IpAddress[0] `
  -DestinationPortRange 80 `
  -Access "Allow"

$nsgRuleWebWAF = New-AzNetworkSecurityRuleConfig `
  -Name "inboundWebRule"  `
  -Protocol "Tcp" `
  -Direction "Inbound" `
  -Priority 1002 `
  -SourceAddressPrefix * `
  -SourcePortRange * `
  -DestinationAddressPrefix $agwPip.IpAddress[0] `
  -DestinationPortRange 80 `
  -Access "Allow"

  $nsgRuleWAFAgwAllow = New-AzNetworkSecurityRuleConfig `
  -Name "inboundAGWallow"  `
  -Protocol "Tcp" `
  -Direction "Inbound" `
  -Priority 1005 `
  -SourceAddressPrefix * `
  -SourcePortRange * `
  -DestinationAddressPrefix $agwPip.IpAddress[0] `
  -DestinationPortRange "65200-65535" `
  -Access "Allow"
# Creating an inbound "deny-all" network security group rule 
$nsgRuleDenyAll = New-AzNetworkSecurityRuleConfig `
  -Name "denyAllRule"  `
  -Protocol * `
  -Direction "Inbound" `
  -Priority 1500 `
  -SourceAddressPrefix * `
  -SourcePortRange * `
  -DestinationAddressPrefix * `
  -DestinationPortRange * `
  -Access "Deny"

# Creating a network security groups
$nsg = New-AzNetworkSecurityGroup `
-ResourceGroupName $rg.Name `
-Location $rg.Location `
-Name "sgDMZ" `
-SecurityRules $nsgRuleExternalSSH,$nsgRuleWeb,$nsgRuleInternalSSH,$nsgRuleWAFAgwAllow,$nsgRuleDenyAll

$nsgWAF = New-AzNetworkSecurityGroup `
-ResourceGroupName $rg.Name `
-Location $rg.Location `
-Name "sgWAF" `
-SecurityRules $nsgRuleWebWAF,$nsgRuleWAFAgwAllow,$nsgRuleDenyAll

$nsgBE = New-AzNetworkSecurityGroup `
-ResourceGroupName $rg.Name `
-Location $rg.Location `
-Name "sgBE" `
-SecurityRules $nsgRuleDenyAll

$nsgCORE = New-AzNetworkSecurityGroup `
-ResourceGroupName $rg.Name `
-Location $rg.Location `
-Name "sgCORE" `
-SecurityRules $nsgRuleDenyAll

#Creating VNet
$subnetConfigWAF = New-AzVirtualNetworkSubnetConfig `
  -Name "WAF" `
  -AddressPrefix '10.0.0.0/24' `
  -NetworkSecurityGroup $nsgWAF
$subnetConfigDMZ = New-AzVirtualNetworkSubnetConfig `
  -Name "DMZ" `
  -AddressPrefix '10.0.1.0/24' `
  -NetworkSecurityGroup $nsg
$subnetConfigBE = New-AzVirtualNetworkSubnetConfig `
  -Name "BE" `
  -AddressPrefix '10.0.2.0/24' `
  -NetworkSecurityGroup $nsgBE
$subnetConfigCORE = New-AzVirtualNetworkSubnetConfig `
  -Name "CORE" `
  -AddressPrefix '10.0.3.0/24' `
  -NetworkSecurityGroup $nsgCORE
$vnet = New-AzVirtualNetwork `
    -Name 'myVNet' `
    -ResourceGroupName $rg.Name `
    -Location $rg.Location `
    -AddressPrefix '10.0.0.0/16' `
    -Subnet $subnetConfigWAF, $subnetConfigDMZ, $subnetConfigBE, $subnetConfigCORE
    



# Creating a public IP addresses and specifying a DNS names

$servicePip = New-AzPublicIpAddress `
  -ResourceGroupName $rg.Name `
  -Location $rg.Location `
  -AllocationMethod Static `
  -Name "servicePip"

$webPip = New-AzPublicIpAddress `
  -ResourceGroupName $rg.Name `
  -Location $rg.Location `
  -AllocationMethod Static `
  -Name "webPip"

$agwPip = New-AzPublicIpAddress `
  -ResourceGroupName $rg.Name `
  -Location $rg.Location `
  -AllocationMethod Static `
  -Name "agwPip" `
  -Sku "Standard"`
  -DomainNameLabel "agwpip-wizz-ngen"
  
# Creating a virtual network cards and associating with public IP addresses and NSG
$serviceNic = New-AzNetworkInterface `
-ResourceGroupName $rg.Name `
-Name "serviceNic" `
-Location $rg.Location `
-SubnetId $vnet.Subnets[1].Id `
-PublicIpAddressId $servicePip.Id `
-NetworkSecurityGroupId $dmzNsg.Id

$webNic = New-AzNetworkInterface `
-ResourceGroupName $rg.Name `
-Name "webNic" `
-Location $rg.Location `
-SubnetId $vnet.Subnets[1].Id `
-PublicIpAddressId $webPip.Id `
-NetworkSecurityGroupId $dmzNsg.Id

# Defining a credential object
$securePassword = ConvertTo-SecureString ' ' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Creating a virtual machine configuration
$webVmConfig = New-AzVMConfig `
  -VMName "webVM" `
  -VMSize "Standard_A1_v2" | `
Set-AzVMOperatingSystem `
  -Linux `
  -ComputerName "webVM" `
  -Credential $cred `
  -DisablePasswordAuthentication | `
Set-AzVMSourceImage `
  -PublisherName "Canonical" `
  -Offer "UbuntuServer" `
  -Skus "18.04-LTS" `
  -Version "latest" | `
Add-AzVMNetworkInterface `
  -Id $webNic.Id

  $serviceVmConfig = New-AzVMConfig `
  -VMName "serviceVM" `
  -VMSize "Standard_A1_v2" | `
Set-AzVMOperatingSystem `
  -Linux `
  -ComputerName "serviceVM" `
  -Credential $cred `
  -DisablePasswordAuthentication | `
Set-AzVMSourceImage `
  -PublisherName "Canonical" `
  -Offer "UbuntuServer" `
  -Skus "18.04-LTS" `
  -Version "latest" | `
Add-AzVMNetworkInterface `
  -Id $serviceNic.Id

  # Configuring the SSH keys
$sshPublicKey = Get-Content ~/.ssh/id_rsa.pub
Add-AzVMSshPublicKey `
  -VM $serviceVmConfig `
  -KeyData $sshPublicKey `
  -Path "/home/azureuser/.ssh/authorized_keys"

  Add-AzVMSshPublicKey `
  -VM $webVmConfig `
  -KeyData $sshPublicKey `
  -Path "/home/azureuser/.ssh/authorized_keys"

# Creating a virtual machines
  New-AzVM `
  -ResourceGroupName $rg.Name `
  -Location $rg.Location `
  -VM $serviceVmConfig `
  -Verbose

  New-AzVM `
  -ResourceGroupName $rg.Name `
  -Location $rg.Location `
  -VM $webVmConfig `
  -Verbose

  
# Creating a Application Gateway(AGW) configuration
$agwIpConfig = New-AzApplicationGatewayIPConfiguration `
-Name "myAgwIpConfig" `
-SubnetId $vnet.Subnets[1].Id

$feIpConfig = New-AzApplicationGatewayFrontendIPConfig `
-Name "myAgwFrontendIpConfig" `
-PublicIPAddress $agwPip

$frontendport = New-AzApplicationGatewayFrontendPort `
-Name "myFrontendPort" `
-Port 80

$bePool = New-AzApplicationGatewayBackendAddressPool `
-Name "myAgwBackendPool" `
-BackendIPAddresses $webPip.IpAddress[0]

$poolSettings = New-AzApplicationGatewayBackendHttpSetting `
-Name myPoolSettings `
-Port 80 `
-Protocol Http `
-CookieBasedAffinity Enabled `
-RequestTimeout 30

$defaultListener = New-AzApplicationGatewayHttpListener `
-Name "myAgwListener" `
-Protocol "Http" `
-FrontendIPConfiguration $feIpConfig `
-FrontendPort $frontendport

$frontendRule = New-AzApplicationGatewayRequestRoutingRule `
-Name "rule1" `
-RuleType "Basic" `
-HttpListener $defaultlistener `
-BackendAddressPool $bePool `
-BackendHttpSettings $poolSettings

# Creating an application gateway

$sku = New-AzApplicationGatewaySku `
  -Name "Standard_v2" `
  -Tier "Standard_v2" `
  -Capacity 2

  New-AzApplicationGateway `
  -Name "myAppGateway" `
  -ResourceGroupName $rg.Name `
  -Location $rg.Location `
  -BackendAddressPools $bePool `
  -BackendHttpSettingsCollection $poolSettings `
  -FrontendIpConfigurations $feIpConfig `
  -GatewayIpConfigurations $agwIpConfig `
  -FrontendPorts $frontendport `
  -HttpListeners $defaultlistener `
  -RequestRoutingRules $frontendRule `
  -Sku $sku

  
  # Generating a random value
$Random=(New-Guid).ToString().Substring(0,8)
$myTmProfile="myTmProfile$Random"

#Configuring a Traffic Manager Profile

New-AzTrafficManagerProfile `
-Name $myTmProfile `
-ResourceGroupName $rg.Name `
-TrafficRoutingMethod Priority `
-MonitorPath '/' `
-MonitorProtocol "HTTP" `
-RelativeDnsName $myTmProfile `
-Ttl 30 `
-MonitorPort 80

New-AzTrafficManagerEndpoint -Name "webEndPoint" `
-ResourceGroupName $rg.Name `
-ProfileName "$myTmProfile" `
-Type "AzureEndpoints" `
-TargetResourceId $agwPip.Id `
-EndpointStatus "Enabled"
 