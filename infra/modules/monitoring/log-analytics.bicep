// ============================================================================
// Log Analytics Workspace - AVD 監視用
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('データ保持期間 (日)')
param retentionInDays int = 30

@description('タグ')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// --- AVD 用ソリューション ---
resource avdInsights 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'WindowsEventForwarding(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  plan: {
    name: 'WindowsEventForwarding(${logAnalyticsWorkspace.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/WindowsEventForwarding'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

// --- Outputs ---
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
