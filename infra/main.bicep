// ============================================================================
// Main Bicep - AVD Hub-and-Spoke 環境 オーケストレーション
// ============================================================================
// 構成:
//   Hub VNet:   Azure Firewall + AD Domain Controller + Azure Bastion
//   Spoke VNets: 各 Spoke に AVD Host Pool + Session Hosts
//   VNet Peering: Hub ⇔ 各 Spoke
//   監視: Log Analytics Workspace
// ============================================================================

targetScope = 'subscription'

// ======================== パラメータ ========================

@description('デプロイ先リージョン')
param location string = 'japaneast'

@description('リソース名プレフィックス')
param prefix string = 'hok-avd'

@description('リソースグループ名')
param resourceGroupName string = '${prefix}-rg'

@description('管理者ユーザー名')
param adminUsername string

@description('管理者パスワード')
@secure()
param adminPassword string

@description('AD ドメイン名')
param domainName string = 'hok.local'

@description('ドメイン参加用ユーザー名 (UPN形式: user@domain)')
param domainJoinUsername string

@description('ドメイン参加用パスワード')
@secure()
param domainJoinPassword string

@description('Spoke 定義の配列')
param spokes array = [
  {
    name: 'spoke01'
    vnetAddressPrefix: '10.1.0.0/16'
    sessionHostSubnetPrefix: '10.1.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4s_v5'
  }
  {
    name: 'spoke02'
    vnetAddressPrefix: '10.2.0.0/16'
    sessionHostSubnetPrefix: '10.2.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4s_v5'
  }
  {
    name: 'spoke03'
    vnetAddressPrefix: '10.3.0.0/16'
    sessionHostSubnetPrefix: '10.3.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4s_v5'
  }
]

@description('ホストプール登録トークンの有効期限 (ISO 8601)')
param tokenExpirationTime string

@description('タグ')
param tags object = {
  environment: 'demo'
  project: 'HOK-AVD'
  managedBy: 'Bicep'
}

// ======================== リソースグループ ========================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ======================== Log Analytics ========================

module logAnalytics 'modules/monitoring/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  scope: rg
  params: {
    location: location
    prefix: prefix
    tags: tags
  }
}

// ======================== Hub ネットワーク ========================

module hubVnet 'modules/network/hub-vnet.bicep' = {
  name: 'deploy-hub-vnet'
  scope: rg
  params: {
    location: location
    prefix: prefix
    tags: tags
  }
}

// ======================== Azure Firewall ========================

module firewall 'modules/network/firewall.bicep' = {
  name: 'deploy-firewall'
  scope: rg
  params: {
    location: location
    prefix: prefix
    firewallSubnetId: hubVnet.outputs.firewallSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    spokeSubnetPrefixes: [for spoke in spokes: spoke.sessionHostSubnetPrefix]
    tags: tags
  }
}

// ======================== AD Domain Controller ========================

module domainController 'modules/ad/domain-controller.bicep' = {
  name: 'deploy-dc'
  scope: rg
  params: {
    location: location
    prefix: prefix
    subnetId: hubVnet.outputs.adSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    domainName: domainName
    tags: tags
  }
}

// ======================== Spoke ネットワーク (ループ) ========================

module spokeVnets 'modules/network/spoke-vnet.bicep' = [
  for (spoke, i) in spokes: {
    name: 'deploy-${spoke.name}-vnet'
    scope: rg
    params: {
      location: location
      prefix: prefix
      spokeName: spoke.name
      vnetAddressPrefix: spoke.vnetAddressPrefix
      sessionHostSubnetPrefix: spoke.sessionHostSubnetPrefix
      hubVnetId: hubVnet.outputs.hubVnetId
      firewallPrivateIp: firewall.outputs.firewallPrivateIp
      dnsServers: [
        domainController.outputs.adVmPrivateIp
      ]
      tags: tags
    }
  }
]

// ======================== Hub → Spoke Peering (ループ) ========================

module hubToSpokePeerings 'modules/network/hub-to-spoke-peering.bicep' = [
  for (spoke, i) in spokes: {
    name: 'deploy-hub-to-${spoke.name}-peering'
    scope: rg
    params: {
      hubVnetName: hubVnet.outputs.hubVnetName
      spokeVnetId: spokeVnets[i].outputs.spokeVnetId
      spokeName: spoke.name
    }
  }
]

// ======================== AVD Host Pool / Workspace (Spoke ごと) ========================

module avdHostPools 'modules/avd/host-pool.bicep' = [
  for (spoke, i) in spokes: {
    name: 'deploy-${spoke.name}-hostpool'
    scope: rg
    params: {
      location: location
      prefix: prefix
      spokeName: spoke.name
      logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
      tokenExpirationTime: tokenExpirationTime
      tags: tags
    }
  }
]

// ======================== AVD Session Hosts (Spoke ごと) ========================

module sessionHosts 'modules/avd/session-host.bicep' = [
  for (spoke, i) in spokes: {
    name: 'deploy-${spoke.name}-session-hosts'
    scope: rg
    params: {
      location: location
      prefix: prefix
      spokeName: spoke.name
      sessionHostCount: spoke.sessionHostCount
      vmSize: spoke.sessionHostVmSize
      subnetId: spokeVnets[i].outputs.sessionHostSubnetId
      adminUsername: adminUsername
      adminPassword: adminPassword
      domainName: domainName
      domainJoinUsername: domainJoinUsername
      domainJoinPassword: domainJoinPassword
      hostPoolName: avdHostPools[i].outputs.hostPoolName
      hostPoolRegistrationToken: avdHostPools[i].outputs.hostPoolRegistrationToken
      tags: tags
    }
    dependsOn: [
      hubToSpokePeerings[i]
    ]
  }
]

// ======================== Outputs ========================

output resourceGroupName string = rg.name
output hubVnetId string = hubVnet.outputs.hubVnetId
output firewallPrivateIp string = firewall.outputs.firewallPrivateIp
output adVmPrivateIp string = domainController.outputs.adVmPrivateIp
output spokeVnetIds array = [for (spoke, i) in spokes: spokeVnets[i].outputs.spokeVnetId]
output hostPoolNames array = [for (spoke, i) in spokes: avdHostPools[i].outputs.hostPoolName]
