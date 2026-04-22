// ============================================================================
// Hub Virtual Network - Azure Firewall + AD + Bastion 用
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Hub VNet のアドレス空間')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Azure Firewall サブネットのアドレスプレフィックス')
param firewallSubnetPrefix string = '10.0.1.0/26'

@description('AD サブネットのアドレスプレフィックス')
param adSubnetPrefix string = '10.0.2.0/24'

@description('Azure Bastion サブネットのアドレスプレフィックス')
param bastionSubnetPrefix string = '10.0.3.0/26'

@description('タグ')
param tags object = {}

// --- NSG for AD Subnet ---
resource adNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-nsg-ad'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowAD-TCP'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '53'    // DNS
            '88'    // Kerberos
            '135'   // RPC
            '389'   // LDAP
            '445'   // SMB
            '464'   // Kerberos change/set password
            '636'   // LDAPS
            '3268'  // Global Catalog
            '3269'  // Global Catalog SSL
            '49152-65535' // RPC dynamic ports
          ]
        }
      }
      {
        name: 'AllowAD-UDP'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Udp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '53'    // DNS
            '88'    // Kerberos
            '123'   // NTP
            '389'   // LDAP
            '464'   // Kerberos change/set password
          ]
        }
      }
    ]
  }
}

// --- Hub Virtual Network ---
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet-hub'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        // Azure Firewall 用サブネット（名前は固定）
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
      {
        name: 'snet-ad'
        properties: {
          addressPrefix: adSubnetPrefix
          networkSecurityGroup: {
            id: adNsg.id
          }
        }
      }
      {
        // Azure Bastion 用サブネット（名前は固定）
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

// --- Azure Bastion ---
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-pip-bastion'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: '${prefix}-bastion'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: hubVnet.properties.subnets[2].id
          }
        }
      }
    ]
  }
}

// --- Outputs ---
output hubVnetId string = hubVnet.id
output hubVnetName string = hubVnet.name
output firewallSubnetId string = hubVnet.properties.subnets[0].id
output adSubnetId string = hubVnet.properties.subnets[1].id
output bastionSubnetId string = hubVnet.properties.subnets[2].id
