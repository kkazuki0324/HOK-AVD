# HOK-AVD - Azure Virtual Desktop デモ環境

お客様向け AVD ハンズオン / デモ環境を Bicep (IaC) で自動構築するプロジェクトです。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Azure Subscription                                                         │
│                                                                             │
│  ┌──────────────────────────────┐  ┌──────────────────────────────────────┐ │
│  │  Hub VNet (10.0.0.0/16)      │  │ Spoke01 VNet (10.1.0.0/16) [Pooled] │ │
│  │                              │  │ ┌────────────────────────────────┐   │ │
│  │  ┌────────────────────────┐  │  │ │ Session Hosts (マルチセッション)│   │ │
│  │  │ Azure Firewall         │  │◄─┤ │ Host Pool + FSLogix Storage   │   │ │
│  │  │ (10.0.1.0/26)          │  │  │ └────────────────────────────────┘   │ │
│  │  └────────────────────────┘  │  └──────────────────────────────────────┘ │
│  │                              │                                           │
│  │  ┌────────────────────────┐  │  ┌──────────────────────────────────────┐ │
│  │  │ AD Domain Controller   │  │  │ Spoke02 VNet (10.2.0.0/16) [Pooled] │ │
│  │  │ (10.0.2.0/24)          │  │  │ ┌────────────────────────────────┐   │ │
│  │  └────────────────────────┘  │◄─┤ │ Session Hosts (マルチセッション)│   │ │
│  │                              │  │ │ Host Pool + FSLogix Storage   │   │ │
│  │  ┌────────────────────────┐  │  │ └────────────────────────────────┘   │ │
│  │  │ Azure Bastion          │  │  └──────────────────────────────────────┘ │
│  │  │ (10.0.3.0/26)          │  │                                           │
│  │  └────────────────────────┘  │  ┌────────────────────────────────────────┐│
│  └──────────────────────────────┘  │ Spoke03 VNet (10.3.0.0/16) [Personal] ││
│          VNet Peering ⇔            │ ┌────────────────────────────────┐     ││
│                                 ◄──┤ │ Session Hosts (シングルセッション)│     ││
│                                    │ │ Host Pool + FSLogix Storage   │     ││
│  ┌──────────────────────────────┐  │ └────────────────────────────────┘     ││
│  │  監視基盤                     │  └────────────────────────────────────────┘│
│  │  Log Analytics + DCR          │                                           │
│  │  AVD Insights Workbook        │                                           │
│  │  Azure Monitor Agent (AMA)    │                                           │
│  │  アラートルール (4種)          │                                           │
│  └──────────────────────────────┘                                            │
│     全 Spoke の通信は Azure Firewall 経由 (UDR)                              │
│     プロファイルは FSLogix で Azure Files に外出し                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 主な構成要素

| コンポーネント                                    | 説明                                                                                  |
| ------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **Hub VNet**                                      | Azure Firewall, AD DC, Bastion を配置する中央ネットワーク                             |
| **Azure Firewall**                                | 全 Spoke の AVD 必須 FQDN / ネットワークルール、M365 通信許可                         |
| **AD Domain Controller**                          | Windows Server 2022, AD DS を自動プロモーション                                       |
| **Azure Bastion**                                 | 管理用の安全な RDP アクセス                                                           |
| **Spoke VNets (複数)**                            | 各 Spoke に Session Host + Host Pool、UDR で Firewall 経由                            |
| **AVD Host Pool - Pooled (マルチセッション)**     | BreadthFirst / 複数ユーザー共有、Win11 Multi-session + M365 Apps                      |
| **AVD Host Pool - Personal (シングルセッション)** | 1ユーザー1VM 専用割り当て、Win11 Enterprise                                           |
| **FSLogix Profile Container**                     | Azure Files Premium + プライベートエンドポイント、プロファイル外出し                  |
| **AVD Insights 監視基盤**                         | DCR + AMA + Workbook + アラート (Session Host障害, 入力遅延, FSLogix, 接続エラー)     |
| **AVD Scaling Plan**                              | 平日 8:00 自動起動 / 18:00 自動停止、ランプアップ・ランプダウン制御                   |
| **Auto-Shutdown (DevTestLab)**                    | 18:00 JST 強制シャットダウン (セーフティネット)                                       |
| **Log Analytics**                                 | Firewall / Host Pool / Workspace の診断ログ + パフォーマンスカウンター + イベントログ |

## フォルダ構成

```
infra/
├── main.bicep                                # メインオーケストレーション (subscription scope)
├── main.bicepparam                           # パラメータファイル
└── modules/
    ├── ad/
    │   └── domain-controller.bicep           # AD DC VM + AD DS インストール
    ├── avd/
    │   ├── host-pool.bicep                   # Host Pool (Pooled/Personal), App Group, Workspace
    │   ├── scaling-plan.bicep                # AVD Scaling Plan (スケジュール起動/停止)
    │   └── session-host.bicep                # Session Host VM + ドメイン参加 + AVD Agent + FSLogix + AMA + Auto-Shutdown
    ├── monitoring/
    │   ├── log-analytics.bicep               # Log Analytics + DCR + Workbook + アラート
    │   └── avd-insights-workbook.json        # AVD Insights Workbook テンプレート
    ├── network/
    │   ├── hub-vnet.bicep                    # Hub VNet + Bastion
    │   ├── spoke-vnet.bicep                  # Spoke VNet + NSG + UDR + Peering
    │   ├── hub-to-spoke-peering.bicep        # Hub → Spoke Peering
    │   └── firewall.bicep                    # Azure Firewall + Policy + AVD ルール
    └── storage/
        └── fslogix-storage.bicep             # Azure Files Premium + PE + Private DNS
```

## 監視について

AVD の監視は「難しい」と言われがちですが、本環境では **AVD Insights** をベースに包括的な監視を自動構成しています。

### 収集データ

| カテゴリ                     | 内容                                                                                         |
| ---------------------------- | -------------------------------------------------------------------------------------------- |
| **パフォーマンスカウンター** | CPU, メモリ, ディスク, ネットワーク, ターミナルサービス, ユーザー入力遅延, RemoteFX, FSLogix |
| **イベントログ**             | System/Application (エラー・警告), FSLogix, RDS, ユーザープロファイル, GroupPolicy           |
| **AVD 診断ログ**             | WVDConnections, WVDAgentHealthStatus (Host Pool / Workspace 診断設定)                        |
| **Firewall ログ**            | Network / Application ルール ヒット                                                          |

### アラートルール

| アラート名                         | 重大度 | トリガー条件                         |
| ---------------------------------- | ------ | ------------------------------------ |
| **Session Host 利用不可**          | Sev 1  | Session Host が Available 以外の状態 |
| **ユーザー入力遅延 高**            | Sev 2  | 平均入力遅延 > 2000ms                |
| **FSLogix プロファイルロード遅延** | Sev 2  | 平均ロード時間 > 30秒                |
| **AVD 接続エラー**                 | Sev 1  | 接続が Failed 状態                   |

### AVD Insights Workbook

自動デプロイされる Workbook で以下を可視化:

- 接続サマリー・トレンド・失敗一覧
- Session Host ヘルス状態一覧
- CPU/メモリ/ディスク パフォーマンストレンド
- ユーザー入力遅延 (AVD UX の最重要指標)
- ネットワーク RTT
- FSLogix プロファイルロード時間・エラー
- セッション統計

## FSLogix Profile Container

各 Spoke に **Azure Files Premium** ストレージを自動作成し、FSLogix Profile Container でユーザープロファイルを外出しにしています。

### 構成

- **ストレージ**: FileStorage (Premium_LRS)、100GB クォータ (変更可能)
- **アクセス**: プライベートエンドポイント + Private DNS Zone (パブリックアクセス無効)
- **認証**: AD DS 認証 (Kerberos)
- **FSLogix 設定** (Session Host に自動適用):
  - プロファイルコンテナ: 有効
  - VHD形式: VHDX
  - 最大サイズ: 30GB
  - FlipFlopProfileDirectoryName: 有効
  - DeleteLocalProfileWhenVHDShouldApply: 有効

### デプロイ後の手順 (FSLogix)

1. **ストレージアカウントの AD DS 参加** - `Join-AzStorageAccount` コマンドで AD にコンピューターオブジェクトとして参加
2. **NTFS アクセス許可設定** - ファイル共有をマウントし、ユーザーに適切な NTFS 権限を付与
3. **動作確認** - ユーザーでログインし、`C:\Users\<user>\` 配下に VHDX が作成されることを確認

## マルチセッション / シングルセッション

| タイプ                            | イメージ                                   | ホストプール | ユースケース                     |
| --------------------------------- | ------------------------------------------ | ------------ | -------------------------------- |
| **マルチセッション (Pooled)**     | Win11 Enterprise Multi-session + M365 Apps | BreadthFirst | コスト効率重視、一般ユーザー向け |
| **シングルセッション (Personal)** | Win11 Enterprise                           | Persistent   | パフォーマンス重視、開発者向け   |

`spokes` パラメータの `hostPoolType` で Spoke ごとに指定できます。

## スケジュール起動 / 停止

**平日 8:00 に自動起動、18:00 に自動停止** する設定が組み込まれています。

### 仕組み (2重構成)

| メカニズム                     | 役割             | 動作                                                                                 |
| ------------------------------ | ---------------- | ------------------------------------------------------------------------------------ |
| **AVD Scaling Plan**           | メイン制御       | 7:30 ランプアップ → 8:00 ピーク → 17:30 ランプダウン (30分前通知) → 18:00 オフピーク |
| **Auto-Shutdown (DevTestLab)** | セーフティネット | 毎日 18:00 JST に強制シャットダウン (15分前通知)                                     |

### Pooled ホストプールの場合

| 時間帯                       | 動作                                            |
| ---------------------------- | ----------------------------------------------- |
| 7:30 - 8:00 (ランプアップ)   | 全 Session Host を起動、BreadthFirst 負荷分散   |
| 8:00 - 17:30 (ピーク)        | 全台稼働、BreadthFirst                          |
| 17:30 - 18:00 (ランプダウン) | 30分前にログオフ通知、セッション 0 の VM を停止 |
| 18:00 - 7:30 (オフピーク)    | 全 VM 停止、StartVMOnConnect で必要時のみ起動   |

### Personal ホストプールの場合

| 時間帯                       | 動作                           |
| ---------------------------- | ------------------------------ |
| 7:30 - 8:00 (ランプアップ)   | 全 VM を自動起動               |
| 8:00 - 17:30 (ピーク)        | StartVMOnConnect 有効          |
| 17:30 - 18:00 (ランプダウン) | 切断/ログオフ 30分後に自動停止 |
| 18:00 - 7:30 (オフピーク)    | 切断/ログオフ 5分後に即停止    |

### 必要な権限設定 (デプロイ後)

Scaling Plan が VM を起動/停止するには、`Azure Virtual Desktop` サービスプリンシパルに `Desktop Virtualization Power On Off Contributor` ロールを割り当てる必要があります:

```powershell
# Azure Virtual Desktop サービスプリンシパルの Object ID を取得
$spObjectId = (Get-AzADServicePrincipal -ApplicationId '9cdead84-a844-4324-93f2-b2e6bb768d07').Id

# サブスクリプションレベルでロールを割り当て
New-AzRoleAssignment `
  -ObjectId $spObjectId `
  -RoleDefinitionName 'Desktop Virtualization Power On Off Contributor' `
  -Scope "/subscriptions/$(Get-AzContext | Select-Object -ExpandProperty Subscription | Select-Object -ExpandProperty Id)"
```

### スケジュールのカスタマイズ

`main.bicepparam` で起動・停止時刻を変更できます:

```bicep
param peakStartHour = 9       // ピーク開始を 9:00 に変更
param offPeakStartHour = 19   // 停止を 19:00 に変更
param autoShutdownTime = '1900' // セーフティネットも合わせて変更
```

## 前提条件

- Azure CLI (`az`) がインストール済み
- Azure サブスクリプションへのログイン済み (`az login`)
- サブスクリプションに以下のリソースプロバイダーが登録済み:
  - `Microsoft.DesktopVirtualization`
  - `Microsoft.Compute`
  - `Microsoft.Network`
  - `Microsoft.Insights`
  - `Microsoft.Storage`
- 十分なクォータ (VM, Public IP, Firewall 等)

## デプロイ手順

### 1. リソースプロバイダーの登録

```bash
az provider register --namespace Microsoft.DesktopVirtualization
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.OperationsManagement
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Storage
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
    tokenExpirationTime='2026-04-23T12:00:00Z' \
    alertEmailAddress='admin@example.com'

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
    tokenExpirationTime='2026-04-23T12:00:00Z' \
    alertEmailAddress='admin@example.com'
```

### 3. デプロイ後の手順

1. **AD DC 再起動待ち** - AD DS インストール後、DC が自動再起動します (5-10分)
2. **ドメインユーザー作成** - Bastion 経由で DC にログインし、AVD 用ユーザーを作成
3. **ストレージアカウントの AD 参加** - `Join-AzStorageAccount` で FSLogix ストレージを AD に参加
4. **NTFS 権限設定** - ファイル共有をマウントし、ユーザーごとの NTFS アクセス許可を設定
5. **Scaling Plan の権限設定** - `Azure Virtual Desktop` サービスプリンシパルに `Desktop Virtualization Power On Off Contributor` ロールを割り当て (上記「スケジュール起動/停止」セクション参照)
6. **Application Group へのユーザー割り当て** - Azure Portal > AVD > 各 Spoke の Application Group から割り当て
7. **接続テスト** - [Windows デスクトップクライアント](https://aka.ms/avdclient) または [Web クライアント](https://client.wvd.microsoft.com/arm/webclient/index.html) で接続
8. **監視確認** - Azure Portal > Log Analytics Workspace > AVD Insights Workbook でダッシュボードを確認

## カスタマイズ

### 基本パラメータ

| パラメータ            | デフォルト値 | 説明                                    |
| --------------------- | ------------ | --------------------------------------- |
| `location`            | `japaneast`  | デプロイ先リージョン                    |
| `prefix`              | `hok-avd`    | リソース名プレフィックス                |
| `domainName`          | `hok.local`  | AD ドメイン名                           |
| `fslogixShareQuotaGB` | `100`        | FSLogix プロファイル共有のクォータ (GB) |
| `alertEmailAddress`   | (空)         | アラート通知先メールアドレス            |
| `peakStartHour`       | `8`          | 業務開始 (VM 起動完了) 時刻 (時)        |
| `offPeakStartHour`    | `18`         | 業務終了 (VM 停止) 時刻 (時)            |
| `autoShutdownTime`    | `1800`       | 自動シャットダウン (HHmm, JST)          |

### Spoke 定義 (`spokes` パラメータ)

`main.bicep` または `main.bicepparam` の `spokes` 配列を編集して Spoke を追加・削除できます。

```bicep
param spokes = [
  {
    name: 'spoke01'                         // Spoke 識別名 (リソース名に使用)
    vnetAddressPrefix: '10.1.0.0/16'        // VNet アドレス空間
    sessionHostSubnetPrefix: '10.1.0.0/24'  // Session Host サブネット
    sessionHostCount: 2                      // Session Host 台数
    sessionHostVmSize: 'Standard_D4as_v7'    // VM サイズ
    hostPoolType: 'Pooled'                   // 'Pooled' (マルチ) or 'Personal' (シングル)
  }
]
```

## セキュリティ考慮事項

- 全 Spoke の Session Host のインターネット通信は Azure Firewall を経由 (UDR)
- Firewall ルールは AVD 必須 FQDN のみ許可 (ホワイトリスト方式)
- Firewall ルールは全 Spoke のサブネットを自動的にカバー
- AD DC は Hub VNet 内に隔離、NSG で必要ポートのみ許可
- 各 Spoke の Session Host は NSG で VNet 内通信のみ許可
- 管理アクセスは Azure Bastion 経由 (パブリック IP なし)
- FSLogix ストレージはプライベートエンドポイント経由のみアクセス可能
- ストレージアカウントの公開アクセスは無効
- Boot Diagnostics 有効、Log Analytics による一元監視
- Azure Monitor Agent で全 Session Host からメトリクス・ログ収集

## コスト目安 (3 Spoke 構成)

主要なコスト要因:

- Azure Firewall (Standard): 約 ¥150,000/月
- Session Host VM (D4s_v5 x 2 x 3 Spoke): 約 ¥240,000/月
- AD DC VM (B2ms x 1): 約 ¥10,000/月
- Azure Bastion (Standard): 約 ¥20,000/月
- Azure Files Premium (100GB x 3 Spoke): 約 ¥5,000/月
- Log Analytics (データ量に依存): 約 ¥5,000-15,000/月

> 合計約 ¥430,000-¥440,000/月程度 (リージョン・為替により変動)
>
> **Scaling Plan + Auto-Shutdown により、平日 8:00-18:00 のみ稼働する設定が有効です。**
> 10時間/日 × 22日/月 の稼働であれば、Session Host のコストは約 3分の1 まで削減されます。
