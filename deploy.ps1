# ============================================================================
# AVD Hub-and-Spoke 環境デプロイスクリプト (PowerShell)
# ============================================================================
# 使い方:
#   .\deploy.ps1
# ============================================================================

$ErrorActionPreference = "Stop"

# --- 設定 ---
$DeploymentName = "hok-avd-deploy-$(Get-Date -Format 'yyyyMMddHHmmss')"
$TemplateFile = "infra/main.bicep"
$Location = "japaneast"
$Prefix = "hok-avd"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " HOK AVD 環境デプロイ (複数 Spoke 対応)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# --- パラメータ入力 ---
$AdminUsername = Read-Host "管理者ユーザー名 (20文字以内, @不可, 例: azureadmin)"
if ($AdminUsername.Length -gt 20 -or $AdminUsername -match '[@\\\/\"\[\]:|\<\>+=;,\?\*]') {
    Write-Host "エラー: 管理者ユーザー名は20文字以内で、@等の特殊文字は使用できません。" -ForegroundColor Red
    exit 1
}
$AdminPassword = Read-Host "管理者パスワード" -AsSecureString
$AdminPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))

$DJUsername = Read-Host "ドメイン参加ユーザー名 (UPN形式: user@domain)"
$DJPassword = Read-Host "ドメイン参加パスワード" -AsSecureString
$DJPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($DJPassword))

# トークン有効期限を24時間後に設定
$TokenExpiry = (Get-Date).AddHours(24).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host ""
Write-Host "--- デプロイ構成 ---" -ForegroundColor Yellow
Write-Host "  リージョン:      $Location"
Write-Host "  プレフィックス:   $Prefix"
Write-Host "  管理者:          $AdminUsername"
Write-Host "  Spoke数:         3 (spoke01, spoke02, spoke03)"
Write-Host "  トークン有効期限: $TokenExpiry"
Write-Host "  ※Spoke 構成は infra/main.bicepparam で変更可能"
Write-Host "--------------------"
Write-Host ""

# --- What-if 検証 ---
Write-Host "[1/3] デプロイ前の検証 (what-if)..." -ForegroundColor Green
az deployment sub what-if `
    --name "$DeploymentName-whatif" `
    --location $Location `
    --template-file $TemplateFile `
    --parameters `
    prefix=$Prefix `
    adminUsername=$AdminUsername `
    adminPassword=$AdminPasswordPlain `
    domainJoinUsername=$DJUsername `
    domainJoinPassword=$DJPasswordPlain `
    tokenExpirationTime=$TokenExpiry

Write-Host ""
$Confirm = Read-Host "上記の変更内容でデプロイしますか？ (y/N)"
if ($Confirm -ne "y" -and $Confirm -ne "Y") {
    Write-Host "デプロイを中止しました。" -ForegroundColor Yellow
    exit 0
}

# --- デプロイ実行 ---
Write-Host "[2/3] デプロイ実行中..." -ForegroundColor Green
az deployment sub create `
    --name $DeploymentName `
    --location $Location `
    --template-file $TemplateFile `
    --parameters `
    prefix=$Prefix `
    adminUsername=$AdminUsername `
    adminPassword=$AdminPasswordPlain `
    domainJoinUsername=$DJUsername `
    domainJoinPassword=$DJPasswordPlain `
    tokenExpirationTime=$TokenExpiry

# --- 結果表示 ---
Write-Host "[3/3] デプロイ完了!" -ForegroundColor Green
Write-Host ""
Write-Host "--- デプロイ結果 ---" -ForegroundColor Yellow
az deployment sub show `
    --name $DeploymentName `
    --query "properties.outputs" `
    --output table

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " デプロイ完了" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Yellow
Write-Host "  1. DC の再起動完了を待つ (AD DS インストール後自動再起動)"
Write-Host "  2. Azure Portal で各 Spoke の AVD Host Pool の Session Host 状態を確認"
Write-Host "  3. 各 Spoke の Application Group にユーザーを割り当て"
Write-Host "  4. AVD クライアントで接続テスト"
