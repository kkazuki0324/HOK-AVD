// ============================================================================
// Azure Virtual Desktop - Host Pool, Application Group, Workspace
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Spoke の識別名')
param spokeName string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('ホストプールの種類 (Pooled / Personal)')
@allowed(['Pooled', 'Personal'])
param hostPoolType string = 'Pooled'

@description('負荷分散アルゴリズム')
@allowed(['BreadthFirst', 'DepthFirst'])
param loadBalancerType string = 'BreadthFirst'

@description('最大セッション数 (ホストあたり)')
param maxSessionLimit int = 10

@description('ホストプール登録トークンの有効期限 (ISO 8601)')
param tokenExpirationTime string

@description('カスタム RDP プロパティ')
param customRdpProperty string = 'audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:;redirectclipboard:i:1;redirectcomports:i:0;redirectprinters:i:1;redirectsmartcards:i:0;screen mode id:i:2;use multimon:i:1;videoplaybackmode:i:1;enablerdsaadauth:i:0;'

@description('タグ')
param tags object = {}

// --- Host Pool ---
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-08-preview' = {
  name: '${prefix}-${spokeName}-hp'
  location: location
  tags: tags
  properties: {
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    maxSessionLimit: maxSessionLimit
    preferredAppGroupType: 'Desktop'
    startVMOnConnect: true
    validationEnvironment: false
    customRdpProperty: customRdpProperty
    registrationInfo: {
      expirationTime: tokenExpirationTime
      registrationTokenOperation: 'Update'
    }
  }
}

// --- Desktop Application Group ---
resource appGroup 'Microsoft.DesktopVirtualization/applicationGroups@2024-04-08-preview' = {
  name: '${prefix}-${spokeName}-dag'
  location: location
  tags: tags
  properties: {
    hostPoolArmPath: hostPool.id
    applicationGroupType: 'Desktop'
    friendlyName: '${prefix} ${spokeName} デスクトップ'
  }
}

// --- Workspace ---
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2024-04-08-preview' = {
  name: '${prefix}-${spokeName}-ws'
  location: location
  tags: tags
  properties: {
    friendlyName: '${prefix} ${spokeName} Workspace'
    applicationGroupReferences: [
      appGroup.id
    ]
  }
}

// --- Host Pool Diagnostics ---
resource hostPoolDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-${spokeName}-hp-diag'
  scope: hostPool
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// --- Workspace Diagnostics ---
resource workspaceDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-${spokeName}-ws-diag'
  scope: workspace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// --- Outputs ---
output hostPoolId string = hostPool.id
output hostPoolName string = hostPool.name
output hostPoolRegistrationToken string = hostPool.properties.registrationInfo.token
output appGroupId string = appGroup.id
output workspaceId string = workspace.id
