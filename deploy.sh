#!/bin/bash
# ============================================================================
# AVD Hub-and-Spoke 環境デプロイスクリプト (複数 Spoke 対応)
# ============================================================================
# 使い方:
#   chmod +x deploy.sh
#   ./deploy.sh
# ============================================================================

set -euo pipefail

# --- 設定 ---
DEPLOYMENT_NAME="hok-avd-deploy-$(date +%Y%m%d%H%M%S)"
TEMPLATE_FILE="infra/main.bicep"
LOCATION="japaneast"
PREFIX="hok-avd"

echo "=========================================="
echo " HOK AVD 環境デプロイ (複数 Spoke 対応)"
echo "=========================================="

# --- パラメータ入力 ---
read -p "管理者ユーザー名: " ADMIN_USERNAME
read -sp "管理者パスワード: " ADMIN_PASSWORD
echo ""
read -p "ドメイン参加ユーザー名 (UPN形式: user@domain): " DJ_USERNAME
read -sp "ドメイン参加パスワード: " DJ_PASSWORD
echo ""

# トークン有効期限を24時間後に設定
TOKEN_EXPIRY=$(date -u -d "+24 hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+24H +%Y-%m-%dT%H:%M:%SZ)

echo ""
echo "--- デプロイ構成 ---"
echo "  リージョン:     $LOCATION"
echo "  プレフィックス:  $PREFIX"
echo "  管理者:         $ADMIN_USERNAME"
echo "  Spoke数:        3 (spoke01, spoke02, spoke03)"
echo "  トークン有効期限: $TOKEN_EXPIRY"
echo "  ※Spoke 構成は infra/main.bicepparam で変更可能"
echo "--------------------"
echo ""

# --- What-if 検証 ---
echo "[1/3] デプロイ前の検証 (what-if)..."
az deployment sub what-if \
  --name "$DEPLOYMENT_NAME-whatif" \
  --location "$LOCATION" \
  --template-file "$TEMPLATE_FILE" \
  --parameters \
    prefix="$PREFIX" \
    adminUsername="$ADMIN_USERNAME" \
    adminPassword="$ADMIN_PASSWORD" \
    domainJoinUsername="$DJ_USERNAME" \
    domainJoinPassword="$DJ_PASSWORD" \
    tokenExpirationTime="$TOKEN_EXPIRY"

echo ""
read -p "上記の変更内容でデプロイしますか？ (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "デプロイを中止しました。"
  exit 0
fi

# --- デプロイ実行 ---
echo "[2/3] デプロイ実行中..."
az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$TEMPLATE_FILE" \
  --parameters \
    prefix="$PREFIX" \
    adminUsername="$ADMIN_USERNAME" \
    adminPassword="$ADMIN_PASSWORD" \
    domainJoinUsername="$DJ_USERNAME" \
    domainJoinPassword="$DJ_PASSWORD" \
    tokenExpirationTime="$TOKEN_EXPIRY"

# --- 結果表示 ---
echo "[3/3] デプロイ完了!"
echo ""
echo "--- デプロイ結果 ---"
az deployment sub show \
  --name "$DEPLOYMENT_NAME" \
  --query "properties.outputs" \
  --output table

echo ""
echo "=========================================="
echo " デプロイ完了"
echo "=========================================="
echo ""
echo "次のステップ:"
echo "  1. DC の再起動完了を待つ (AD DS インストール後自動再起動)"
echo "  2. Azure Portal で各 Spoke の AVD Host Pool の Session Host 状態を確認"
echo "  3. 各 Spoke の Application Group にユーザーを割り当て"
echo "  4. AVD クライアントで接続テスト"
