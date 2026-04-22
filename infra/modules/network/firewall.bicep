// ============================================================================
// Azure Firewall - AVD 通信に必要なルール付き
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Azure Firewall サブネット ID')
param firewallSubnetId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('タグ')
param tags object = {}

@description('全 Spoke のセッションホストサブネットアドレス一覧 (Firewall ルール用)')
param spokeSubnetPrefixes array

// --- Firewall Public IP ---
resource firewallPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-pip-fw'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- Firewall Policy ---
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: '${prefix}-fw-policy'
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    dnsSettings: {
      enableProxy: true
    }
  }
}

// --- AVD 必須 FQDN ルール ---
resource avdRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: firewallPolicy
  name: 'avd-rules'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'avd-required-fqdns'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AVD-Service'
            protocols: [
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: [
              '*.wvd.microsoft.com'
              '*.servicebus.windows.net'
              '*.prod.warm.ingest.monitor.core.windows.net'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AVD-Authentication'
            protocols: [
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: [
              'login.microsoftonline.com'
              'login.windows.net'
              '*.identity.azure.net'
              '*.login.microsoftonline.com'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AVD-Agent-Updates'
            protocols: [
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: [
              '*.blob.core.windows.net'
              'mrsglobalsteus2prod.blob.core.windows.net'
              'wvdportalstorageblob.blob.core.windows.net'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Windows-Activation-KMS'
            protocols: [
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: [
              'kms.core.windows.net'
              'azkms.core.windows.net'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Windows-Update'
            protocols: [
              { protocolType: 'Https', port: 443 }
              { protocolType: 'Http', port: 80 }
            ]
            targetFqdns: [
              '*.update.microsoft.com'
              '*.windowsupdate.com'
              '*.download.windowsupdate.com'
              'ctldl.windowsupdate.com'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Certificate-Validation'
            protocols: [
              { protocolType: 'Https', port: 443 }
              { protocolType: 'Http', port: 80 }
            ]
            targetFqdns: [
              '*.digicert.com'
              '*.verisign.com'
              '*.msocsp.com'
              '*.microsoft.com'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Microsoft365'
            protocols: [
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: [
              '*.office365.com'
              '*.office.com'
              '*.microsoftonline.com'
              '*.microsoft.com'
              '*.live.com'
              '*.office.net'
              '*.onenote.com'
              '*.sharepoint.com'
              '*.teams.microsoft.com'
            ]
            sourceAddresses: spokeSubnetPrefixes
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'avd-network-rules'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'DNS'
            ipProtocols: ['TCP', 'UDP']
            sourceAddresses: spokeSubnetPrefixes
            destinationAddresses: ['10.0.2.0/24']
            destinationPorts: ['53']
          }
          {
            ruleType: 'NetworkRule'
            name: 'KMS-Activation'
            ipProtocols: ['TCP']
            sourceAddresses: spokeSubnetPrefixes
            destinationAddresses: ['23.102.135.246']
            destinationPorts: ['1688']
          }
          {
            ruleType: 'NetworkRule'
            name: 'NTP'
            ipProtocols: ['UDP']
            sourceAddresses: spokeSubnetPrefixes
            destinationAddresses: ['*']
            destinationPorts: ['123']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AD-Communication'
            ipProtocols: ['TCP', 'UDP']
            sourceAddresses: spokeSubnetPrefixes
            destinationAddresses: ['10.0.2.0/24']
            destinationPorts: [
              '53'
              '88'
              '123'
              '135'
              '389'
              '445'
              '464'
              '636'
              '3268'
              '3269'
              '49152-65535'
            ]
          }
        ]
      }
    ]
  }
}

// --- Azure Firewall ---
resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: '${prefix}-fw'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          publicIPAddress: {
            id: firewallPip.id
          }
          subnet: {
            id: firewallSubnetId
          }
        }
      }
    ]
  }
}

// --- Diagnostic Settings ---
resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-fw-diag'
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// --- Outputs ---
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallId string = firewall.id
output firewallPolicyId string = firewallPolicy.id
