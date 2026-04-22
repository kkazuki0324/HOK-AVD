# HOK-AVD - Azure Virtual Desktop デモ環境

お客様向け AVD ハンズオン / デモ環境を Bicep (IaC) で自動構築するプロジェクトです。

## アーキテクチャ

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Azure Subscription                                                        │
│                                                                            │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────────┐  │
│  │  Hub VNet (10.0.0.0/16)     │  │  Spoke01 VNet (10.1.0.0/16)        │  │
│  │                             │  │  ┌───────────────────────────────┐  │  │
│  │  ┌───────────────────────┐  │  │  │ Session Hosts (10.1.0.0/24)  │  │  │
│  │  │ Azure Firewall        │  │◄─┤  │ Host Pool + Workspace        │  │  │
│  │  │ (10.0.1.0/26)         │  │  │  └───────────────────────────────┘  │  │
│  │  └───────────────────────┘  │  └─────────────────────────────────────┘  │
│  │                             │                                           │
│  │  ┌───────────────────────┐  │  ┌─────────────────────────────────────┐  │
│  │  │ AD Domain Controller  │  │  │  Spoke02 VNet (10.2.0.0/16)        │  │
│  │  │ (10.0.2.0/24)         │  │  │  ┌───────────────────────────────┐  │  │
│  │  └───────────────────────┘  │◄─┤  │ Session Hosts (10.2.0.0/24)  │  │  │
│  │                             │  │  │ Host Pool + Workspace        │  │  │
│  │  ┌───────────────────────┐  │  │  └───────────────────────────────┘  │  │
│  │  │ Azure Bastion         │  │  └─────────────────────────────────────┘  │
│  │  │ (10.0.3.0/26)         │  │                                           │
│  │  └───────────────────────┘  │  ┌─────────────────────────────────────┐  │
│  └─────────────────────────────┘  │  Spoke03 VNet (10.3.0.0/16)        │  │
│          VNet Peering ⇔           │  ┌───────────────────────────────┐  │  │
│                                ◄──┤  │ Session Hosts (10.3.0.0/24)  │  │  │
│                                   │  │ Host Pool + Workspace        │  │  │
│  ┌─────────────────────────────┐  │  └───────────────────────────────┘  │  │
│  │  Log Analytics (監視・診断)  │  └─────────────────────────────────────┘  │
│  └─────────────────────────────┘                                           │
│     全 Spoke の通信は Azure Firewall 経由 (UDR)                             │
│     各 Spoke に専用の Host Pool / Application Group / Workspace            │
└────────────────────────────────────────────────────────────────────────────┘
```

## 主な構成要素

| コンポーネント                 | 説明                                                          |
| ------------------------------ | ------------------------------------------------------------- |
| **Hub VNet**                   | Azure Firewall, AD DC, Bastion を配置する中央ネットワーク     |
| **Azure Firewall**             | 全 Spoke の AVD 必須 FQDN / ネットワークルール、M365 通信許可 |
| **AD Domain Controller**       | Windows Server 2022, AD DS を自動プロモーション               |
| **Azure Bastion**              | 管理用の安全な RDP アクセス                                   |
| **Spoke VNets (複数)**         | 各 Spoke に Session Host + Host Pool、UDR で Firewall 経由    |
| **AVD Host Pool (Spoke ごと)** | Pooled / BreadthFirst、StartVMOnConnect 有効                  |
| **Session Hosts**              | Windows 11 Enterprise Multi-session + M365 Apps               |
| **Log Analytics**              | Firewall / 全 Host Pool / Workspace の診断ログ                |

## フォルダ構成

```
infra/
├── main.bicep                          # メインオーケストレーション (subscription scope)
├── main.bicepparam                     # パラメータファイル
└── modules/
    ├── ad/
    │   └── domain-controller.bicep     # AD DC VM + AD DS インストール
    ├── avd/
    │   ├── host-pool.bicep             # Host Pool, App Group, Workspace
    │   └── session-host.bicep          # Session Host VM + ドメイン参加 + AVD Agent
    ├── monitoring/
    │   └── log-analytics.bicep         # Log Analytics Workspace
    └── network/
        ├── hub-vnet.bicep              # Hub VNet + Bastion
        ├── spoke-vnet.bicep            # Spoke VNet + NSG + UDR + Peering
        ├── hub-to-spoke-peering.bicep  # Hub → Spoke Peering
        └── firewall.bicep              # Azure Firewall + Policy + AVD ルール
```

## 前提条件

- Azure CLI (`az`) がインストール済み
- Azure サブスクリプションへのログイン済み (`az login`)
- サブスクリプションに以下のリソースプロバイダーが登録済み:
  - `Microsoft.DesktopVirtualization`
  - `Microsoft.Compute`
  - `Microsoft.Network`
- 十分なクォータ (VM, Public IP, Firewall 等)

## デプロイ手順

### 1. リソースプロバイダーの登録

```bash
az provider register --namespace Microsoft.DesktopVirtualization
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.OperationsManagement
```

### 2. デプロイの実行

#### PowerShell (推奨)

```powershell
.\deploy.ps1
```

#### Bash

```bash
chmod +x deploy.sh
./deploy.sh
```

#### 手動 (az cli)

```bash
# What-if 検証
az deployment sub what-if \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters \
    prefix=hok-avd \
    adminUsername=azureadmin \
    adminPassword='<パスワード>' \
    domainJoinUsername='azureadmin@hok.local' \
    domainJoinPassword='<パスワード>' \
    tokenExpirationTime='2026-04-23T12:00:00Z'

# デプロイ
az deployment sub create \
  --location japaneast \
  --template-file infra/main.bicep \
  --parameters \
    prefix=hok-avd \
    adminUsername=azureadmin \
    adminPassword='<パスワード>' \
    domainJoinUsername='azureadmin@hok.local' \
    domainJoinPassword='<パスワード>' \
    tokenExpirationTime='2026-04-23T12:00:00Z'
```

### 3. デプロイ後の手順

1. **AD DC 再起動待ち** - AD DS インストール後、DC が自動再起動します (5-10分)
2. **ドメインユーザー作成** - Bastion 経由で DC にログインし、AVD 用ユーザーを作成
3. **Application Group へのユーザー割り当て** - Azure Portal > AVD > 各 Spoke の Application Group から割り当て
4. **接続テスト** - [Windows デスクトップクライアント](https://aka.ms/avdclient) または [Web クライアント](https://client.wvd.microsoft.com/arm/webclient/index.html) で接続

## カスタマイズ

### 基本パラメータ

| パラメータ   | デフォルト値 | 説明                     |
| ------------ | ------------ | ------------------------ |
| `location`   | `japaneast`  | デプロイ先リージョン     |
| `prefix`     | `hok-avd`    | リソース名プレフィックス |
| `domainName` | `hok.local`  | AD ドメイン名            |

### Spoke 定義 (`spokes` パラメータ)

`main.bicep` または `main.bicepparam` の `spokes` 配列を編集して Spoke を追加・削除できます。

```bicep
param spokes = [
  {
    name: 'spoke01'                         // Spoke 識別名 (リソース名に使用)
    vnetAddressPrefix: '10.1.0.0/16'        // VNet アドレス空間
    sessionHostSubnetPrefix: '10.1.0.0/24'  // Session Host サブネット
    sessionHostCount: 2                      // Session Host 台数
    sessionHostVmSize: 'Standard_D4s_v5'    // VM サイズ
  }
  // Spoke を追加するにはここにオブジェクトを追加
]
```

## セキュリティ考慮事項

- 全 Spoke の Session Host のインターネット通信は Azure Firewall を経由 (UDR)
- Firewall ルールは AVD 必須 FQDN のみ許可 (ホワイトリスト方式)
- Firewall ルールは全 Spoke のサブネットを自動的にカバー
- AD DC は Hub VNet 内に隔離、NSG で必要ポートのみ許可
- 各 Spoke の Session Host は NSG で VNet 内通信のみ許可
- 管理アクセスは Azure Bastion 経由 (パブリック IP なし)
- Boot Diagnostics 有効、Log Analytics による一元監視

## コスト目安 (3 Spoke 構成)

主要なコスト要因:

- Azure Firewall (Standard): 約 ¥150,000/月
- Session Host VM (D4s_v5 x 2 x 3 Spoke): 約 ¥240,000/月
- AD DC VM (B2ms x 1): 約 ¥10,000/月
- Azure Bastion (Standard): 約 ¥20,000/月

> 合計約 ¥420,000/月程度 (リージョン・為替により変動)
> デモ利用時は使い終わったら VM を停止してコストを削減してください。
