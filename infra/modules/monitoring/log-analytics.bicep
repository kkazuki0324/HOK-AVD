// ============================================================================
// 監視基盤 - Log Analytics + AVD Insights + DCR + アラート
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('データ保持期間 (日)')
param retentionInDays int = 30

@description('アラート通知先メールアドレス (空の場合アラートアクションなし)')
param alertEmailAddress string = ''

@description('タグ')
param tags object = {}

// ======================== Log Analytics Workspace ========================

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

// ======================== AVD Insights 用パフォーマンスカウンター ========================

// Data Collection Rule: Session Host のパフォーマンス + イベントログ収集
resource avdDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${prefix}-dcr-avd-insights'
  location: location
  tags: tags
  properties: {
    description: 'AVD Insights 用 DCR - パフォーマンスカウンター + イベントログ'
    dataSources: {
      performanceCounters: [
        {
          name: 'avdPerformanceCounters'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 30
          counterSpecifiers: [
            // CPU
            '\\Processor Information(_Total)\\% Processor Time'
            // メモリ
            '\\Memory\\Available Mbytes'
            '\\Memory\\Page Faults/sec'
            // ディスク
            '\\LogicalDisk(C:)\\% Free Space'
            '\\LogicalDisk(C:)\\Avg. Disk Queue Length'
            '\\LogicalDisk(C:)\\Avg. Disk sec/Transfer'
            '\\LogicalDisk(C:)\\Current Disk Queue Length'
            '\\PhysicalDisk(_Total)\\Avg. Disk Queue Length'
            '\\PhysicalDisk(_Total)\\Avg. Disk sec/Read'
            '\\PhysicalDisk(_Total)\\Avg. Disk sec/Write'
            // ネットワーク
            '\\Network Interface(*)\\Bytes Total/sec'
            // ターミナルサービス
            '\\Terminal Services\\Active Sessions'
            '\\Terminal Services\\Inactive Sessions'
            '\\Terminal Services\\Total Sessions'
            // ユーザー入力遅延 (AVD の重要指標)
            '\\User Input Delay per Process(*)\\Max Input Delay'
            '\\User Input Delay per Session(*)\\Max Input Delay'
            // RemoteFX Graphics (AVD パフォーマンス)
            '\\RemoteFX Graphics(*)\\Average Encoding Time'
            '\\RemoteFX Graphics(*)\\Frames Skipped/Second - Insufficient Network Resources'
            '\\RemoteFX Graphics(*)\\Frames Skipped/Second - Insufficient Server Resources'
            '\\RemoteFX Network(*)\\Current TCP RTT'
            '\\RemoteFX Network(*)\\Current UDP Bandwidth'
            // FSLogix
            '\\FSLogix Apps(*)\\Profile Load Time (ms)'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'avdEventLogs'
          streams: ['Microsoft-Event']
          xPathQueries: [
            // システムイベント (エラー・警告)
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
            // アプリケーションイベント (エラー・警告)
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            // FSLogix イベント
            'Microsoft-FSLogix-Apps/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            'Microsoft-FSLogix-Apps/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            // RemoteDesktopServices イベント
            'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            // ユーザープロファイルイベント
            'Microsoft-Windows-User Profile Service/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            // GroupPolicy イベント
            'Microsoft-Windows-GroupPolicy/Operational!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'la-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf']
        destinations: ['la-destination']
      }
      {
        streams: ['Microsoft-Event']
        destinations: ['la-destination']
      }
    ]
  }
}

// ======================== アラートルール ========================

// アクショングループ (メール通知)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = if (!empty(alertEmailAddress)) {
  name: '${prefix}-ag-avd'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'AVDAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'AVD-Admin'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// アラート: Session Host が利用不可
resource sessionHostUnavailableAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${prefix}-alert-sh-unavailable'
  location: location
  tags: tags
  properties: {
    displayName: 'AVD Session Host 利用不可'
    description: 'Session Host が Available 以外の状態になった場合にアラート'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            WVDAgentHealthStatus
            | where TimeGenerated > ago(5m)
            | where Status != "Available"
            | summarize count() by SessionHostName, Status
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: !empty(alertEmailAddress) ? [actionGroup.id] : []
    }
  }
}

// アラート: ユーザー入力遅延が高い
resource inputDelayAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${prefix}-alert-input-delay'
  location: location
  tags: tags
  properties: {
    displayName: 'AVD ユーザー入力遅延 高'
    description: 'ユーザー入力遅延が 2000ms を超えた場合にアラート (UX 劣化の兆候)'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where TimeGenerated > ago(15m)
            | where ObjectName == "User Input Delay per Session"
            | where CounterName == "Max Input Delay"
            | summarize AvgDelay = avg(CounterValue) by Computer
            | where AvgDelay > 2000
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: !empty(alertEmailAddress) ? [actionGroup.id] : []
    }
  }
}

// アラート: FSLogix プロファイルロード遅延
resource fslogixLoadAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${prefix}-alert-fslogix-load'
  location: location
  tags: tags
  properties: {
    displayName: 'FSLogix プロファイルロード遅延'
    description: 'FSLogix プロファイルのロード時間が 30秒を超えた場合にアラート'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where TimeGenerated > ago(15m)
            | where ObjectName == "FSLogix Apps"
            | where CounterName == "Profile Load Time (ms)"
            | summarize AvgLoadTime = avg(CounterValue) by Computer
            | where AvgLoadTime > 30000
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: !empty(alertEmailAddress) ? [actionGroup.id] : []
    }
  }
}

// アラート: 接続エラー
resource connectionErrorAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${prefix}-alert-connection-error'
  location: location
  tags: tags
  properties: {
    displayName: 'AVD 接続エラー'
    description: 'AVD への接続が失敗した場合にアラート'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            WVDConnections
            | where TimeGenerated > ago(5m)
            | where State == "Failed"
            | summarize FailureCount = count() by CorrelationId, UserName
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: !empty(alertEmailAddress) ? [actionGroup.id] : []
    }
  }
}

// ======================== AVD Insights Workbook ========================

resource avdInsightsWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('${prefix}-workbook-avd-insights')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: '${prefix} - AVD Insights ダッシュボード'
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
    serializedData: loadTextContent('avd-insights-workbook.json')
  }
}

// ======================== Outputs ========================

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output dcrId string = avdDcr.id
