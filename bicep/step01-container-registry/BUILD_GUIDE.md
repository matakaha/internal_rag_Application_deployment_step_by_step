# Azure Container Registry ビルド・プッシュガイド

このガイドでは、GitHub Actions Self-hosted Runnerコンテナーイメージをビルドし、Azure Container Registryにプッシュする方法を説明します。

## 前提条件

- Azure CLIがインストールされていること
- Azure Container Registry が作成されていること（Step 01のBicepデプロイ完了）

## 方法1: ACR Tasks使用（推奨、Docker不要）

**メリット**:
- ✅ ローカルにDockerのインストール不要
- ✅ クラウド上で高速ビルド
- ✅ ネットワーク帯域を消費しない

> **⚠️ 注意**: ACR Tasksを使用する場合も、ビルドエージェント接続のため一時的にパブリックアクセス有効化とネットワークルール変更が必要です。

### 使用方法

```powershell
# 環境変数の設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ACR_NAME = "acrinternalragdev"  # 実際のACR名に変更

# 1. パブリックアクセスを一時的に有効化
az acr update --name $ACR_NAME --public-network-enabled true

# 2. ネットワークルールのデフォルトアクションをAllowに変更
az acr update --name $ACR_NAME --default-action Allow

# 3. ACR上で直接ビルドとプッシュ
az acr build `
  --registry $ACR_NAME `
  --image github-runner:latest `
  --image github-runner:1.0.0 `
  --file Dockerfile `
  .

# 4. イメージ確認
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table

# 5. ネットワークルールをDenyに戻す
az acr update --name $ACR_NAME --default-action Deny

# 6. パブリックアクセスを無効化
az acr update --name $ACR_NAME --public-network-enabled false
```

---

## 方法2: ローカルDockerでビルド（オプション）

**前提条件**: Docker Desktop または Podman がインストールされていること

## 使用方法

### PowerShell

```powershell
# 環境変数の設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ACR_NAME = "acrinternalragdev"  # 実際のACR名に変更
$VERSION = "1.0.0"

# スクリプトの実行
.\build-and-push.ps1 -ResourceGroup $RESOURCE_GROUP -AcrName $ACR_NAME -Version $VERSION
```

### Bash (WSL/Linux/macOS)

```bash
# 環境変数の設定
RESOURCE_GROUP="rg-internal-rag-dev"
ACR_NAME="acrinternalragdev"  # 実際のACR名に変更
VERSION="1.0.0"

# スクリプトの実行
./build-and-push.sh "$RESOURCE_GROUP" "$ACR_NAME" "$VERSION"
```

## スクリプト内容

### build-and-push.ps1

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$AcrName,
    
    [Parameter(Mandatory=$false)]
    [string]$Version = "latest"
)

# ACRにログイン
Write-Host "Logging in to ACR: $AcrName" -ForegroundColor Green
az acr login --name $AcrName

# イメージをビルド
Write-Host "Building Docker image..." -ForegroundColor Green
docker build -t "${AcrName}.azurecr.io/github-runner:latest" .

# latestタグをプッシュ
Write-Host "Pushing latest tag..." -ForegroundColor Green
docker push "${AcrName}.azurecr.io/github-runner:latest"

# バージョンタグを作成してプッシュ
if ($Version -ne "latest") {
    Write-Host "Tagging and pushing version: $Version" -ForegroundColor Green
    docker tag "${AcrName}.azurecr.io/github-runner:latest" "${AcrName}.azurecr.io/github-runner:${Version}"
    docker push "${AcrName}.azurecr.io/github-runner:${Version}"
}

# イメージ一覧を表示
Write-Host "`nContainer images in ACR:" -ForegroundColor Green
az acr repository show-tags --name $AcrName --repository github-runner --output table

Write-Host "`nDone!" -ForegroundColor Green
```

### build-and-push.sh

```bash
#!/bin/bash
set -e

RESOURCE_GROUP=$1
ACR_NAME=$2
VERSION=${3:-latest}

if [ -z "$RESOURCE_GROUP" ] || [ -z "$ACR_NAME" ]; then
    echo "Usage: $0 <resource-group> <acr-name> [version]"
    exit 1
fi

# ACRにログイン
echo "Logging in to ACR: $ACR_NAME"
az acr login --name "$ACR_NAME"

# イメージをビルド
echo "Building Docker image..."
docker build -t "${ACR_NAME}.azurecr.io/github-runner:latest" .

# latestタグをプッシュ
echo "Pushing latest tag..."
docker push "${ACR_NAME}.azurecr.io/github-runner:latest"

# バージョンタグを作成してプッシュ
if [ "$VERSION" != "latest" ]; then
    echo "Tagging and pushing version: $VERSION"
    docker tag "${ACR_NAME}.azurecr.io/github-runner:latest" "${ACR_NAME}.azurecr.io/github-runner:${VERSION}"
    docker push "${ACR_NAME}.azurecr.io/github-runner:${VERSION}"
fi

# イメージ一覧を表示
echo ""
echo "Container images in ACR:"
az acr repository show-tags --name "$ACR_NAME" --repository github-runner --output table

echo ""
echo "Done!"
```

## トラブルシューティング

### エラー: ACRへのログインに失敗

**原因**: `publicNetworkAccess: Disabled` の場合、ローカルからアクセス不可

**対処法**:
```powershell
# 一時的にパブリックアクセスを有効化
az acr update --name $ACR_NAME --public-network-enabled true

# スクリプト実行
.\build-and-push.ps1 -ResourceGroup $RESOURCE_GROUP -AcrName $ACR_NAME -Version $VERSION

# パブリックアクセスを無効化
az acr update --name $ACR_NAME --public-network-enabled false
```

### エラー: Dockerデーモンが起動していない

**対処法**:
- Docker Desktopを起動してください
- または、Windows Serviceを再起動: `Restart-Service docker`

### エラー: 権限不足でACRにプッシュできない

**対処法**:
```powershell
# Azure CLIで再ログイン
az login

# ACRの権限を確認
az role assignment list --assignee <your-user-principal-id> --resource-group $RESOURCE_GROUP
```

必要に応じて `AcrPush` ロールを付与:
```powershell
az role assignment create `
  --assignee <your-user-principal-id> `
  --role AcrPush `
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"
```
