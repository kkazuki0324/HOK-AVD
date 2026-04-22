// ============================================================================
// Main Bicep - AVD Hub-and-Spoke 環境 オーケストレーション
// ============================================================================
// 構成:
//   Hub VNet:   Azure Firewall + AD Domain Controller + Azure Bastion
//   Spoke VNets: 各 Spoke に AVD Host Pool + Session Hosts
//   VNet Peering: Hub ⇔ 各 Spoke
//   監視: Log Analytics + AVD Insights (DCR + Workbook + アラート)
//   プロファイル: FSLogix Profile Container (Azure Files Premium)
//   セッション: マルチセッション (Pooled) + シングルセッション (Personal) 対応
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

@description('Spoke 定義の配列 (hostPoolType: Pooled=マルチセッション / Personal=シングルセッション)')
param spokes array = [
  {
    name: 'spoke01'
    vnetAddressPrefix: '10.1.0.0/16'
    sessionHostSubnetPrefix: '10.1.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4s_v5'
    hostPoolType: 'Pooled'
  }
  {
    name: 'spoke02'
    vnetAddressPrefix: '10.2.0.0/16'
    sessionHostSubnetPrefix: '10.2.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4s_v5'
    hostPoolType: 'Pooled'
  }
  {
    name: 'spoke03'
    vnetAddressPrefix: '10.3.0.0/16'
    sessionHostSubnetPrefix: '10.3.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4s_v5'
    hostPoolType: 'Personal'
  }
]

@description('ホストプール登録トークンの有効期限 (ISO 8601)')
param tokenExpirationTime string

@description('FSLogix プロファイル共有のクォータ (GB)')
param fslogixShareQuotaGB int = 100

@description('アラート通知先メールアドレス (空の場合はアラートアクションなし)')
param alertEmailAddress string = ''

@description('スケーリングプラン: ピーク開始時刻 (時)')
param peakStartHour int = 8

@description('スケーリングプラン: ピーク開始時刻 (分)')
param peakStartMinute int = 0

@description('スケーリングプラン: オフピーク開始時刻 (時)')
param offPeakStartHour int = 18

@description('スケーリングプラン: オフピーク開始時刻 (分)')
param offPeakStartMinute int = 0

@description('自動シャットダウン時刻 (HHmm 形式, セーフティネット)')
param autoShutdownTime string = '1800'

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

// ======================== Log Analytics + 監視基盤 ========================

module logAnalytics 'modules/monitoring/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  scope: rg
  params: {
    location: location
    prefix: prefix
    alertEmailAddress: alertEmailAddress
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

// ======================== FSLogix Storage (Spoke ごと) ========================

module fslogixStorage 'modules/storage/fslogix-storage.bicep' = [
  for (spoke, i) in spokes: {
    name: 'deploy-${spoke.name}-fslogix-storage'
    scope: rg
    params: {
      location: location
      prefix: prefix
      spokeName: spoke.name
      subnetId: spokeVnets[i].outputs.sessionHostSubnetId
      vnetId: spokeVnets[i].outputs.spokeVnetId
      shareQuotaGB: fslogixShareQuotaGB
      tags: tags
    }
    dependsOn: [
      hubToSpokePeerings[i]
    ]
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
      hostPoolType: spoke.hostPoolType
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
      hostPoolType: spoke.hostPoolType
      fslogixProfileSharePath: fslogixStorage[i].outputs.profileSharePath
      dcrId: logAnalytics.outputs.dcrId
      autoShutdownTime: autoShutdownTime
      tags: tags
    }
    dependsOn: [
      hubToSpokePeerings[i]
    ]
  }
]

// ======================== AVD Scaling Plan (Spoke ごと) ========================

module scalingPlans 'modules/avd/scaling-plan.bicep' = [
  for (spoke, i) in spokes: {
    name: 'deploy-${spoke.name}-scaling-plan'
    scope: rg
    params: {
      location: location
      prefix: prefix
      spokeName: spoke.name
      hostPoolId: avdHostPools[i].outputs.hostPoolId
      hostPoolType: spoke.hostPoolType
      peakStartHour: peakStartHour
      peakStartMinute: peakStartMinute
      offPeakStartHour: offPeakStartHour
      offPeakStartMinute: offPeakStartMinute
      tags: tags
    }
  }
]

// ======================== Outputs ========================

output resourceGroupName string = rg.name
output hubVnetId string = hubVnet.outputs.hubVnetId
output firewallPrivateIp string = firewall.outputs.firewallPrivateIp
output adVmPrivateIp string = domainController.outputs.adVmPrivateIp
output spokeVnetIds array = [for (spoke, i) in spokes: spokeVnets[i].outputs.spokeVnetId]
output hostPoolNames array = [for (spoke, i) in spokes: avdHostPools[i].outputs.hostPoolName]
output fslogixSharePaths array = [for (spoke, i) in spokes: fslogixStorage[i].outputs.profileSharePath]
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
