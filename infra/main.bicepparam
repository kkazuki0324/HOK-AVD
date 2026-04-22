using './main.bicep'

// ============================================================================
// パラメータ - 環境に合わせて変更してください
// ============================================================================

param location = 'japaneast'
param prefix = 'hok-avd'
param resourceGroupName = 'hok-avd-rg'

// --- 認証情報 (デプロイ時に入力) ---
param adminUsername = '' // ← DC / Session Host のローカル管理者
param adminPassword = '' // ← デプロイ時に -p で指定

// --- AD 設定 ---
param domainName = 'hok.local'
param domainJoinUsername = '' // ← 例: admin@hok.local
param domainJoinPassword = '' // ← デプロイ時に -p で指定

// --- Spoke 定義 (追加・削除で Spoke 数を変更可能) ---
// hostPoolType: 'Pooled' = マルチセッション (共有), 'Personal' = シングルセッション (専用)
param spokes = [
  {
    name: 'spoke01'
    vnetAddressPrefix: '10.1.0.0/16'
    sessionHostSubnetPrefix: '10.1.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4as_v7'
    hostPoolType: 'Pooled' // マルチセッション
  }
  {
    name: 'spoke02'
    vnetAddressPrefix: '10.2.0.0/16'
    sessionHostSubnetPrefix: '10.2.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4as_v7'
    hostPoolType: 'Pooled' // マルチセッション
  }
  {
    name: 'spoke03'
    vnetAddressPrefix: '10.3.0.0/16'
    sessionHostSubnetPrefix: '10.3.0.0/24'
    sessionHostCount: 2
    sessionHostVmSize: 'Standard_D4as_v7'
    hostPoolType: 'Personal' // シングルセッション (1ユーザー1VM)
  }
]

// --- FSLogix プロファイル共有設定 ---
param fslogixShareQuotaGB = 100

// --- 監視設定 ---
param alertEmailAddress = '' // ← アラート通知先メール (空=アクションなし)

// --- スケジュール設定 (VM 起動・停止) ---
param peakStartHour = 8 // ← ピーク (業務) 開始時刻: 8:00
param peakStartMinute = 0
param offPeakStartHour = 18 // ← オフピーク (停止) 開始時刻: 18:00
param offPeakStartMinute = 0
param autoShutdownTime = '1800' // ← 自動シャットダウン 18:00 JST (セーフティネット)

// --- ホストプール登録トークン有効期限 (デプロイ日から 24h 後を設定) ---
param tokenExpirationTime = '' // ← 例: 2026-04-23T12:00:00Z
