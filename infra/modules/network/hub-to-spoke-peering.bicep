// ============================================================================
// Hub → Spoke VNet Peering (Hub 側に定義)
// ============================================================================

@description('Hub VNet 名')
param hubVnetName string

@description('Spoke VNet ID')
param spokeVnetId string

@description('Spoke の識別名')
param spokeName string

// --- Hub → Spoke Peering ---
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${hubVnetName}/hub-to-${spokeName}'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
