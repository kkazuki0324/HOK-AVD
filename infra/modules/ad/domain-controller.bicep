// ============================================================================
// Active Directory Domain Controller VM
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('AD サブネット ID')
param subnetId string

@description('VM のサイズ')
param vmSize string = 'Standard_D2as_v7'

@description('管理者ユーザー名')
param adminUsername string

@description('管理者パスワード')
@secure()
param adminPassword string

@description('AD ドメイン名')
param domainName string

@description('タグ')
param tags object = {}

// --- NIC ---
resource adNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-nic-dc01'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.2.4'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

// --- Domain Controller VM ---
resource adVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${prefix}-vm-dc01'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'DC01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
        timeZone: 'Tokyo Standard Time'
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: '${prefix}-osdisk-dc01'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
      dataDisks: [
        {
          name: '${prefix}-datadisk-dc01'
          diskSizeGB: 32
          lun: 0
          createOption: 'Empty'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: adNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// --- AD DS インストール用 PowerShell スクリプト ---
resource adDscExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: adVm
  name: 'InstallADDS'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File C:\\setup-adds.ps1'
    }
    protectedSettings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -Command "Get-Disk | Where-Object PartitionStyle -eq RAW | Initialize-Disk -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false; Install-WindowsFeature AD-Domain-Services -IncludeManagementTools; Import-Module ADDSDeployment; Install-ADDSForest -DomainName ${domainName} -DomainNetbiosName ${split(domainName, '.')[0]} -SafeModeAdministratorPassword (ConvertTo-SecureString \'${adminPassword}\' -AsPlainText -Force) -DatabasePath F:\\NTDS -LogPath F:\\NTDS -SysvolPath F:\\SYSVOL -InstallDns:$true -Force:$true -NoRebootOnCompletion:$false"'
    }
  }
}

// --- Outputs ---
output adVmId string = adVm.id
output adVmPrivateIp string = adNic.properties.ipConfigurations[0].properties.privateIPAddress
