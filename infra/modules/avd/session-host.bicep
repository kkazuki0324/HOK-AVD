// ============================================================================
// AVD Session Host VMs - マルチセッション / シングルセッション対応
// FSLogix + Azure Monitor Agent 統合
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
param vmSize string = 'Standard_D4s_v3'

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

@description('ホストプールタイプ (Pooled=マルチセッション, Personal=シングルセッション)')
@allowed(['Pooled', 'Personal'])
param hostPoolType string = 'Pooled'

@description('FSLogix プロファイル共有の UNC パス')
param fslogixProfileSharePath string = ''

@description('DCR (Data Collection Rule) の ID')
param dcrId string = ''

@description('自動シャットダウン時刻 (HHmm 形式, 例: 1800 = 18:00)')
param autoShutdownTime string = '1800'

@description('自動シャットダウンのタイムゾーン')
param autoShutdownTimeZone string = 'Tokyo Standard Time'

@description('タグ')
param tags object = {}

// --- イメージ参照: ホストプールタイプに応じたイメージを選択 ---
var multiSessionImage = {
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'office-365'
  sku: 'win11-24h2-avd-m365'
  version: 'latest'
}

var singleSessionImage = {
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'windows-11'
  sku: 'win11-24h2-ent'
  version: 'latest'
}

var imageReference = hostPoolType == 'Pooled' ? multiSessionImage : singleSessionImage

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
        imageReference: imageReference
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

// --- FSLogix 設定 (プロファイルコンテナ) ---
resource fslogixExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [
  for i in range(0, sessionHostCount): if (!empty(fslogixProfileSharePath)) {
    parent: sessionHostVm[i]
    name: 'FSLogixConfig'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      typeHandlerVersion: '1.10'
      autoUpgradeMinorVersion: true
      protectedSettings: {
        commandToExecute: 'powershell -ExecutionPolicy Bypass -Command "New-Item -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Force; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name Enabled -Value 1 -Type DWord; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name VHDLocations -Value \'${fslogixProfileSharePath}\' -Type MultiString; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name DeleteLocalProfileWhenVHDShouldApply -Value 1 -Type DWord; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name FlipFlopProfileDirectoryName -Value 1 -Type DWord; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name SizeInMBs -Value 30000 -Type DWord; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name VolumeType -Value VHDX -Type String; Write-Output \'FSLogix configured successfully\'"'
      }
    }
    dependsOn: [
      avdAgentExtension[i]
    ]
  }
]

// --- Azure Monitor Agent ---
resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [
  for i in range(0, sessionHostCount): {
    parent: sessionHostVm[i]
    name: 'AzureMonitorWindowsAgent'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorWindowsAgent'
      typeHandlerVersion: '1.0'
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
    }
    dependsOn: [
      avdAgentExtension[i]
    ]
  }
]

// --- DCR 関連付け ---
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [
  for i in range(0, sessionHostCount): if (!empty(dcrId)) {
    name: '${prefix}-${spokeName}-sh${padLeft(string(i), 2, '0')}-dcr-assoc'
    scope: sessionHostVm[i]
    properties: {
      dataCollectionRuleId: dcrId
    }
    dependsOn: [
      amaExtension[i]
    ]
  }
]

// --- 自動シャットダウン (DevTestLab / セーフティネット) ---
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [
  for i in range(0, sessionHostCount): {
    name: 'shutdown-computevm-${sessionHostVm[i].name}'
    location: location
    tags: tags
    properties: {
      status: 'Enabled'
      taskType: 'ComputeVmShutdownTask'
      dailyRecurrence: {
        time: autoShutdownTime
      }
      timeZoneId: autoShutdownTimeZone
      targetResourceId: sessionHostVm[i].id
      notificationSettings: {
        status: 'Enabled'
        timeInMinutes: 15
        notificationLocale: 'ja'
      }
    }
  }
]

// --- Outputs ---
output sessionHostVmIds array = [for i in range(0, sessionHostCount): sessionHostVm[i].id]
