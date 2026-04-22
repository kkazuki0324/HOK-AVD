// ============================================================================
// FSLogix Profile Container 用 Azure Files ストレージ
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Spoke の識別名')
param spokeName string

@description('Session Host サブネット ID (プライベートエンドポイント用)')
param subnetId string

@description('VNet ID (プライベート DNS ゾーンリンク用)')
param vnetId string

@description('ファイル共有のクォータ (GB)')
param shareQuotaGB int = 100

@description('タグ')
param tags object = {}

// --- ストレージアカウント名 (グローバルで一意, 最大24文字, 英数小文字のみ) ---
var storageAccountName = replace('${prefix}fs${spokeName}', '-', '')

// ======================== ストレージアカウント ========================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: length(storageAccountName) > 24 ? substring(storageAccountName, 0, 24) : storageAccountName
  location: location
  tags: tags
  kind: 'FileStorage'
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AD'
    }
    largeFileSharesState: 'Enabled'
  }
}

// ======================== ファイル共有 ========================

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource profileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: 'fslogix-profiles'
  properties: {
    shareQuota: shareQuotaGB
    enabledProtocols: 'SMB'
    accessTier: 'Premium'
  }
}

// ======================== プライベートエンドポイント ========================

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${prefix}-${spokeName}-pe-fslogix'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${prefix}-${spokeName}-pls-fslogix'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// ======================== プライベート DNS ゾーン ========================

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${spokeName}-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ======================== Outputs ========================

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output profileShareName string = profileShare.name
output profileSharePath string = '\\\\${storageAccount.name}.file.core.windows.net\\${profileShare.name}'
