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
param spokes = [
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

// --- ホストプール登録トークン有効期限 (デプロイ日から 24h 後を設定) ---
param tokenExpirationTime = '' // ← 例: 2026-04-23T12:00:00Z
