// ============================================================================
// Spoke Virtual Network - AVD Session Host 用
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Spoke の識別名 (例: spoke01, spoke02)')
param spokeName string

@description('Spoke VNet のアドレス空間')
param vnetAddressPrefix string

@description('Session Host サブネットのアドレスプレフィックス')
param sessionHostSubnetPrefix string

@description('カスタム DNS サーバー (AD DC の IP)')
param dnsServers array = []

@description('Hub VNet ID (Peering用)')
param hubVnetId string

@description('Azure Firewall のプライベート IP (UDR 用)')
param firewallPrivateIp string

@description('タグ')
param tags object = {}

// --- Route Table (Spoke → Firewall) ---
resource routeTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: '${prefix}-rt-${spokeName}'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// --- NSG for Session Host Subnet ---
resource sessionHostNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-nsg-${spokeName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowVNetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// --- Spoke Virtual Network ---
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet-${spokeName}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: dnsServers
    }
    subnets: [
      {
        name: 'snet-sessionhost'
        properties: {
          addressPrefix: sessionHostSubnetPrefix
          networkSecurityGroup: {
            id: sessionHostNsg.id
          }
          routeTable: {
            id: routeTable.id
          }
        }
      }
    ]
  }
}

// --- VNet Peering: Spoke → Hub ---
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spokeVnet
  name: 'spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// --- Outputs ---
output spokeVnetId string = spokeVnet.id
output spokeVnetName string = spokeVnet.name
output sessionHostSubnetId string = spokeVnet.properties.subnets[0].id
