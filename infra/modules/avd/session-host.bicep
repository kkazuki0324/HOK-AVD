// ============================================================================
// AVD Session Host VMs - 実運用レベルの構成
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Spoke の識別名')
param spokeName string

@description('デプロイする Session Host の台数')
@minValue(1)
@maxValue(50)
param sessionHostCount int = 2

@description('Session Host の VM サイズ')
param vmSize string = 'Standard_D4s_v5'

@description('Session Host サブネット ID')
param subnetId string

@description('管理者ユーザー名')
param adminUsername string

@description('管理者パスワード')
@secure()
param adminPassword string

@description('AD ドメイン名')
param domainName string

@description('ドメイン参加用の OU パス (省略可)')
param ouPath string = ''

@description('ドメイン参加用ユーザー名 (UPN 形式)')
param domainJoinUsername string

@description('ドメイン参加用パスワード')
@secure()
param domainJoinPassword string

@description('AVD Host Pool 名')
param hostPoolName string

@description('AVD Host Pool 登録トークン')
@secure()
param hostPoolRegistrationToken string

@description('タグ')
param tags object = {}

// --- Session Host VMs ---
resource sessionHostNic 'Microsoft.Network/networkInterfaces@2024-05-01' = [
  for i in range(0, sessionHostCount): {
    name: '${prefix}-${spokeName}-nic-sh${padLeft(string(i), 2, '0')}'
    location: location
    tags: tags
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: subnetId
            }
          }
        }
      ]
    }
  }
]

resource sessionHostVm 'Microsoft.Compute/virtualMachines@2024-07-01' = [
  for i in range(0, sessionHostCount): {
    name: '${prefix}-${spokeName}-sh${padLeft(string(i), 2, '0')}'
    location: location
    tags: tags
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      osProfile: {
        computerName: '${spokeName}-sh${padLeft(string(i), 2, '0')}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          provisionVMAgent: true
          enableAutomaticUpdates: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            automaticByPlatformSettings: {
              rebootSetting: 'IfRequired'
            }
            assessmentMode: 'AutomaticByPlatform'
          }
          timeZone: 'Tokyo Standard Time'
        }
      }
      storageProfile: {
        imageReference: {
          // Windows 11 Enterprise Multi-session + Microsoft 365 Apps
          publisher: 'MicrosoftWindowsDesktop'
          offer: 'office-365'
          sku: 'win11-24h2-avd-m365'
          version: 'latest'
        }
        osDisk: {
          name: '${prefix}-${spokeName}-osdisk-sh${padLeft(string(i), 2, '0')}'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: 128
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: sessionHostNic[i].id
          }
        ]
      }
      licenseType: 'Windows_Client'
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
    }
  }
]

// --- ドメイン参加 ---
resource domainJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [
  for i in range(0, sessionHostCount): {
    parent: sessionHostVm[i]
    name: 'JoinDomain'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'JsonADDomainExtension'
      typeHandlerVersion: '1.3'
      autoUpgradeMinorVersion: true
      settings: {
        name: domainName
        ouPath: ouPath
        user: domainJoinUsername
        restart: 'true'
        options: '3' // NETSETUP_JOIN_DOMAIN | NETSETUP_ACCT_CREATE
      }
      protectedSettings: {
        password: domainJoinPassword
      }
    }
  }
]

// --- AVD Agent インストール ---
resource avdAgentExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [
  for i in range(0, sessionHostCount): {
    parent: sessionHostVm[i]
    name: 'AVDAgent'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.PowerShell'
      type: 'DSC'
      typeHandlerVersion: '2.73'
      autoUpgradeMinorVersion: true
      settings: {
        modulesUrl: 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip'
        configurationFunction: 'Configuration.ps1\\AddSessionHost'
        properties: {
          hostPoolName: hostPoolName
          registrationInfoTokenCredential: {
            UserName: 'PLACEHOLDER'
            Password: 'PrivateSettingsRef:RegistrationInfoToken'
          }
          aadJoin: false
        }
      }
      protectedSettings: {
        items: {
          RegistrationInfoToken: hostPoolRegistrationToken
        }
      }
    }
    dependsOn: [
      domainJoinExtension[i]
    ]
  }
]

// --- Outputs ---
output sessionHostVmIds array = [for i in range(0, sessionHostCount): sessionHostVm[i].id]
