# Step 04: GitHub Actionsワークフローの構築

このステップでは、GitHub Actionsを使って閉域Web AppsへCI/CDデプロイするワークフローを構築します。

## 学習目標

このステップを完了すると、以下を理解できます:

- Self-hosted RunnerをContainer Instanceで動的起動
- Key Vaultからのシークレット取得
- vNet内リソースへのデプロイ方法
- GitHub Actionsのベストプラクティス

## 作成される環境

このステップでは、GitHub Actions CI/CD環境を構築します。実際のアプリケーションコードとWorkflowファイルは、[📦 internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo)で提供されています。

### サンプルリポジトリに含まれるファイル

| ファイル | 目的 |
|---------|------|
| `.github/workflows/deploy.yml` | App Service(フロントエンド)用デプロイワークフロー |
| `.github/workflows/deploy-functions.yml` | Azure Functions(バックエンド)用デプロイワークフロー |
| `scripts/setup-runner.ps1` | Runner起動スクリプト |
| `scripts/cleanup-runner.ps1` | Runnerクリーンアップスクリプト |
| `src/app.js` | Node.js/Express フロントエンドアプリ |
| `function_app.py` | Azure Functions バックエンドAPI (Python v2) |
| `requirements.txt` | Python依存関係 |

> **Note**: アプリケーションはフロントエンド(Node.js/Express on App Service)とバックエンド(Python on Azure Functions)の2層構成です。

## 前提条件

- Step 01, 02, 03が完了していること
- [前提条件ドキュメント](../../docs/00-prerequisites.md)の事前準備タスクが完了していること
  - サービスプリンシパル作成済み
  - GitHub Personal Access Token (PAT)取得済み
- フォークまたはクローンするGitHubリポジトリへのアクセス権

## セットアップ手順

### 1. サンプルリポジトリの準備

実際のアプリケーションコードとWorkflowは、サンプルリポジトリを使用します。

#### オプションA: フォークして自分のリポジトリとして使用（推奨）

1. https://github.com/matakaha/internal_rag_Application_sample_repo を開く
2. **Fork** ボタンをクリック
3. 自分のアカウントにフォーク
4. フォークしたリポジトリをクローン
   ```powershell
   git clone https://github.com/<your-username>/internal_rag_Application_sample_repo.git
   cd internal_rag_Application_sample_repo
   ```

#### オプションB: 新しいリポジトリとして作成

```powershell
# サンプルをダウンロード
git clone https://github.com/matakaha/internal_rag_Application_sample_repo.git my-rag-app
cd my-rag-app

# 新しいGitHubリポジトリを作成
gh repo create <org>/<repo-name> --private --source=. --remote=origin --push
```

> **💡 ヒント**: フォークすると、元のリポジトリの更新を受け取りやすくなります。

### 2. GitHub Secretsの設定

> **🔐 重要な変更**: GitHub ActionsからAzureへの認証方式が**Federated Identity (OIDC)**に変更されました。これにより長期的なシークレット(Client Secret)を管理する必要がなくなり、セキュリティが向上します。

#### 必要なSecrets

**OIDC認証方式 (推奨)**:

| Secret名 | 内容 | 取得方法 |
|---------|------|---------|
| `AZURE_CLIENT_ID` | アプリケーション(クライアント)ID | 前提条件で作成したサービスプリンシパル |
| `AZURE_TENANT_ID` | ディレクトリ(テナント)ID | Azureサブスクリプション情報 |
| `AZURE_SUBSCRIPTION_ID` | サブスクリプションID | Azureサブスクリプション情報 |
| `KEY_VAULT_NAME` | Key Vault名 | `kv-gh-runner-<環境名>` |
| `GH_PAT` | Personal Access Token | GitHub Settings |

**Client Secret方式 (非推奨)**:

<details>
<summary>Client Secret方式のSecrets一覧</summary>

| Secret名 | 内容 | 取得方法 |
|---------|------|---------|
| `AZURE_CREDENTIALS` | サービスプリンシパル情報 (JSON) | Step 03で格納したKey Vaultから |
| `KEY_VAULT_NAME` | Key Vault名 | `kv-gh-runner-<環境名>` |
| `GH_PAT` | Personal Access Token | GitHub Settings |

</details>

#### Secretsの設定方法

##### 方法1: OIDC認証 + GitHub CLI使用（最新・推奨）

> **📋 前提条件**: GitHub CLIがインストール済みであること。インストールされていない場合は[方法2](#方法2-github-web-ui手動設定cli不要)を使用してください。

**GitHub CLIのインストール**:
```powershell
# wingetでインストール
winget install --id GitHub.cli

# インストール後、認証
gh auth login
```

**Secretsの設定**:
```powershell
# 環境変数の設定
$KEY_VAULT_NAME = "kv-gh-runner-dev"  # 環境に応じて変更

# OIDC認証用の情報を設定
# (前提条件「3. Azure サービスプリンシパルとFederated Credential作成」で取得した値を使用)

gh secret set AZURE_CLIENT_ID --body $CLIENT_ID
gh secret set AZURE_TENANT_ID --body $TENANT_ID
gh secret set AZURE_SUBSCRIPTION_ID --body $SUBSCRIPTION_ID
gh secret set KEY_VAULT_NAME --body $KEY_VAULT_NAME

# GitHub PATをKey Vaultから取得して設定
$GITHUB_PAT = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "GITHUB-PAT" --query value -o tsv
gh secret set GH_PAT --body $GITHUB_PAT
```

> **💡 ヒント**: 
> - OIDC方式では**CLIENT_SECRET (パスワード)は不要**です
> - Federated Credentialが正しく設定されていれば、GitHub Actionsワークフロー実行時に一時的なトークンが自動発行されます

**Client Secret方式の場合 (非推奨)**:

<details>
<summary>Client Secret方式のGitHub Secrets設定手順</summary>

```powershell
# 1. Key Vaultからサービスプリンシパル情報を取得
$KEY_VAULT_NAME = "kv-gh-runner-dev"  # 環境に応じて変更

$CLIENT_ID = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-ID" --query value -o tsv
$CLIENT_SECRET = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-SECRET" --query value -o tsv
$TENANT_ID = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-TENANT-ID" --query value -o tsv
$SUBSCRIPTION_ID = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-SUBSCRIPTION-ID" --query value -o tsv

# 2. JSON形式でAZURE_CREDENTIALSを作成
$AZURE_CREDENTIALS = @{
  clientId = $CLIENT_ID
  clientSecret = $CLIENT_SECRET
  subscriptionId = $SUBSCRIPTION_ID
  tenantId = $TENANT_ID
} | ConvertTo-Json -Compress

# 3. GitHub Secretsに設定
gh secret set AZURE_CREDENTIALS --body $AZURE_CREDENTIALS
gh secret set KEY_VAULT_NAME --body $KEY_VAULT_NAME

# 4. GitHub PATをKey Vaultから取得して設定
$GITHUB_PAT = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "GITHUB-PAT" --query value -o tsv
gh secret set GH_PAT --body $GITHUB_PAT
```

</details>

> **💡 ヒント**: すべての認証情報をKey Vaultから取得するため、ローカルに機密情報を残しません。

##### 方法2: GitHub Web UI（手動設定、CLI不要）

GitHub CLIをインストールしたくない場合は、以下の手順でWebブラウザから設定できます。

**OIDC認証方式の場合 (推奨)**:

**ステップ1: 必要な値を取得・表示**

```powershell
# 環境変数の設定
$KEY_VAULT_NAME = "kv-gh-runner-dev"  # 環境に応じて変更

# CLIENT_ID, TENANT_ID, SUBSCRIPTION_IDを表示
# (前提条件で作成済みの変数を使用)
Write-Host "\n=== AZURE_CLIENT_ID (以下をコピー) ===" -ForegroundColor Green
Write-Host $CLIENT_ID

Write-Host "\n=== AZURE_TENANT_ID (以下をコピー) ===" -ForegroundColor Green
Write-Host $TENANT_ID

Write-Host "\n=== AZURE_SUBSCRIPTION_ID (以下をコピー) ===" -ForegroundColor Green
Write-Host $SUBSCRIPTION_ID

Write-Host "\n=== KEY_VAULT_NAME (以下をコピー) ===" -ForegroundColor Green
Write-Host $KEY_VAULT_NAME

# GitHub PATをKey Vaultから取得
$GITHUB_PAT = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "GITHUB-PAT" --query value -o tsv
Write-Host "\n=== GH_PAT (以下をコピー) ===" -ForegroundColor Green
Write-Host $GITHUB_PAT
```

**ステップ2: GitHub Web UIでSecretsを設定**

1. GitHubリポジトリを開く
2. **Settings** → **Secrets and variables** → **Actions** に移動
3. **New repository secret** をクリック
4. 以下の5つのSecretを順番に作成:

| Name | Secret (上記で表示された値をコピー&ペースト) |
|------|---------------------------------------------|
| `AZURE_CLIENT_ID` | `$CLIENT_ID`の値 |
| `AZURE_TENANT_ID` | `$TENANT_ID`の値 |
| `AZURE_SUBSCRIPTION_ID` | `$SUBSCRIPTION_ID`の値 |
| `KEY_VAULT_NAME` | `kv-gh-runner-dev` など |
| `GH_PAT` | PATの値 |

5. 各Secretで **Add secret** をクリック

**Client Secret方式の場合 (非推奨)**:

<details>
<summary>Client Secret方式のWeb UI設定手順</summary>

**ステップ1: Key Vaultから値を取得して表示**

```powershell
# 1. Key Vaultからサービスプリンシパル情報を取得
$KEY_VAULT_NAME = "kv-gh-runner-dev"  # 環境に応じて変更

$CLIENT_ID = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-ID" --query value -o tsv
$CLIENT_SECRET = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-SECRET" --query value -o tsv
$TENANT_ID = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-TENANT-ID" --query value -o tsv
$SUBSCRIPTION_ID = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "AZURE-SUBSCRIPTION-ID" --query value -o tsv
$GITHUB_PAT = az keyvault secret show --vault-name $KEY_VAULT_NAME --name "GITHUB-PAT" --query value -o tsv

# 2. AZURE_CREDENTIALS用のJSON文字列を作成・表示
$AZURE_CREDENTIALS_JSON = @"
{
  "clientId": "$CLIENT_ID",
  "clientSecret": "$CLIENT_SECRET",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "tenantId": "$TENANT_ID"
}
"@

Write-Host "`n=== AZURE_CREDENTIALS (以下をコピー) ===" -ForegroundColor Green
Write-Host $AZURE_CREDENTIALS_JSON

Write-Host "`n=== KEY_VAULT_NAME (以下をコピー) ===" -ForegroundColor Green
Write-Host $KEY_VAULT_NAME

Write-Host "`n=== GH_PAT (以下をコピー) ===" -ForegroundColor Green
Write-Host $GITHUB_PAT
```

**ステップ2: GitHub Web UIでSecretsを設定**

1. GitHubリポジトリを開く
2. **Settings** → **Secrets and variables** → **Actions** に移動
3. **New repository secret** をクリック
4. 以下の3つのSecretを順番に作成:

| Name | Secret (上記で表示された値をコピー&ペースト) |
|------|---------------------------------------------|
| `AZURE_CREDENTIALS` | JSON形式の値全体(中括弧`{}`を含む) |
| `KEY_VAULT_NAME` | `kv-gh-runner-dev` など |
| `GH_PAT` | PATの値 |

5. 各Secretで **Add secret** をクリック

</details>

**確認**:
```powershell
# GitHub CLIがある場合のみ確認可能
gh secret list
```

または、GitHub Web UIで Settings → Secrets and variables → Actions を開いて、必要なSecretsが表示されることを確認してください。

**OIDC方式の場合**: 5つのSecret (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, KEY_VAULT_NAME, GH_PAT)  
**Client Secret方式の場合**: 3つのSecret (AZURE_CREDENTIALS, KEY_VAULT_NAME, GH_PAT)

---

## 📦 サンプルアプリケーションリポジトリの利用

**ここまでで、GitHub Actions CI/CD環境の構築は完了しました。**

実際のアプリケーションコード（Workflowファイル、Pythonアプリ、デプロイスクリプト等）は、以下のサンプルリポジトリで提供しています:

### 🔗 [internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo)

このサンプルリポジトリには以下が含まれています:
- ✅ `.github/workflows/deploy.yml` - 完全なGitHub Actionsワークフロー
- ✅ `scripts/` - Self-hosted Runnerセットアップスクリプト
- ✅ `src/` - FlaskベースのRAGチャットアプリケーション
- ✅ `docs/` - ステップバイステップのデプロイガイド

### 🚀 次のステップ

1. **サンプルリポジトリをフォーク/クローン**
   ```powershell
   git clone https://github.com/matakaha/internal_rag_Application_sample_repo.git
   cd internal_rag_Application_sample_repo
   ```

2. **サンプルリポジトリのREADMEに従って進める**
   - [Step 1: 環境準備](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step01-setup-environment.md)
   - [Step 2: データ準備](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step02-data-preparation.md)
   - [Step 3: AI Searchインデックス作成](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step03-indexing.md)
   - [Step 4: アプリケーションデプロイ](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step04-deploy-app.md)
   - [Step 5: テストと運用](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step05-testing.md)

> **💡 重要**: サンプルリポジトリを使用する場合、以下の「3. Workflowファイルの作成」以降の内容は**実施不要**です。サンプルリポジトリに全て実装済みです。

---

## 📝 参考: Workflowファイルの詳細解説

以下は、サンプルリポジトリで使用されているWorkflowファイルの解説です。自分でカスタマイズする場合の参考としてご覧ください。

### Workflowファイルの構成

`.github/workflows/deploy.yml`:

```yaml
name: Deploy to Azure Web Apps

on:
  push:
    branches:
      - main
  workflow_dispatch:

env:
  RESOURCE_GROUP: 'rg-internal-rag-dev'
  WEBAPP_NAME: 'app-internal-rag-dev'
  CONTAINER_GROUP_NAME: 'aci-runner-${{ github.run_id }}'
  VNET_NAME: 'vnet-internal-rag-dev'
  SUBNET_NAME: 'snet-container-instances'
  LOCATION: 'japaneast'

jobs:
  setup-runner:
    runs-on: ubuntu-latest
    outputs:
      runner-name: ${{ steps.create-runner.outputs.runner-name }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Create Container Instance Runner
        id: create-runner
        run: |
          # Runner名を生成
          RUNNER_NAME="runner-${{ github.run_id }}"
          echo "runner-name=$RUNNER_NAME" >> $GITHUB_OUTPUT

          # Key VaultからGitHub PATを取得
          GITHUB_TOKEN=$(az keyvault secret show \
            --vault-name ${{ secrets.KEY_VAULT_NAME }} \
            --name GITHUB-PAT \
            --query value -o tsv)

          # GitHub Runner登録トークン取得
          RUNNER_TOKEN=$(curl -s -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token" \
            | jq -r .token)

          # ACRログインサーバーを取得
          ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer -o tsv)

          # Container Instance作成（ACRイメージを使用）
          # Option 1: Managed Identity使用（推奨）
          az container create \
            --resource-group $RESOURCE_GROUP \
            --name $CONTAINER_GROUP_NAME \
            --image ${ACR_LOGIN_SERVER}/github-runner:latest \
            --acr-identity $MANAGED_IDENTITY_ID \
            --vnet $VNET_NAME \
            --subnet $SUBNET_NAME \
            --location $LOCATION \
            --cpu 2 \
            --memory 4 \
            --restart-policy Never \
            --assign-identity $MANAGED_IDENTITY_ID \
            --environment-variables \
              GITHUB_TOKEN=$GITHUB_TOKEN \
              GITHUB_REPOSITORY=${{ github.repository }}

          # Option 2: ACR Admin User使用（非推奨、テスト環境のみ）
          # ACR_USERNAME=$(az keyvault secret show --vault-name ${{ secrets.KEY_VAULT_NAME }} --name ACR-USERNAME --query value -o tsv)
          # ACR_PASSWORD=$(az keyvault secret show --vault-name ${{ secrets.KEY_VAULT_NAME }} --name ACR-PASSWORD --query value -o tsv)
          # az container create \
          #   --resource-group $RESOURCE_GROUP \
          #   --name $CONTAINER_GROUP_NAME \
          #   --image ${ACR_LOGIN_SERVER}/github-runner:latest \
          #   --registry-login-server $ACR_LOGIN_SERVER \
          #   --registry-username $ACR_USERNAME \
          #   --registry-password $ACR_PASSWORD \
          #   --vnet $VNET_NAME \
          #   --subnet $SUBNET_NAME \
          #   --location $LOCATION \
          #   --cpu 2 \
          #   --memory 4 \
          #   --restart-policy Never \
          #   --environment-variables \
          #     GITHUB_TOKEN=$GITHUB_TOKEN \
          #     GITHUB_REPOSITORY=${{ github.repository }}

          # Runner起動待機
          echo "Waiting for runner to be ready..."
          sleep 60

  build-and-deploy:
    needs: setup-runner
    runs-on: self-hosted
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login (on self-hosted runner)
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Get secrets from Key Vault
        id: get-secrets
        run: |
          # 必要なシークレットをKey Vaultから取得
          PUBLISH_PROFILE=$(az keyvault secret show \
            --vault-name ${{ secrets.KEY_VAULT_NAME }} \
            --name WEBAPP-PUBLISH-PROFILE \
            --query value -o tsv)
          echo "::add-mask::$PUBLISH_PROFILE"
          echo "PUBLISH_PROFILE=$PUBLISH_PROFILE" >> $GITHUB_ENV

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Build application
        run: |
          # アプリケーションのビルド処理
          echo "Building application..."

      - name: Deploy to Azure Web Apps
        uses: azure/webapps-deploy@v2
        with:
          app-name: ${{ env.WEBAPP_NAME }}
          publish-profile: ${{ env.PUBLISH_PROFILE }}
          package: .

  cleanup:
    needs: [setup-runner, build-and-deploy]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Remove Runner from GitHub
        continue-on-error: true
        run: |
          # Key VaultからGitHub PATを取得
          GITHUB_TOKEN=$(az keyvault secret show \
            --vault-name ${{ secrets.KEY_VAULT_NAME }} \
            --name GITHUB-PAT \
            --query value -o tsv)

          # Runner一覧取得
          RUNNERS=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners")

          # 該当Runnerを削除
          RUNNER_ID=$(echo $RUNNERS | jq -r ".runners[] | select(.name==\"${{ needs.setup-runner.outputs.runner-name }}\") | .id")
          
          if [ ! -z "$RUNNER_ID" ]; then
            curl -X DELETE \
              -H "Authorization: token $GITHUB_TOKEN" \
              -H "Accept: application/vnd.github+json" \
              "https://api.github.com/repos/${{ github.repository }}/actions/runners/$RUNNER_ID"
          fi

      - name: Delete Container Instance
        run: |
          az container delete \
            --resource-group $RESOURCE_GROUP \
            --name $CONTAINER_GROUP_NAME \
            --yes
```

## Workflowの詳細解説

### 重要: Azure Container Registry (ACR) の利用

事前にACRにビルドしたRunnerイメージを使用することで、完全閉域環境でのRunner起動を実現します。

#### ACR利用のメリット

| 項目 | 説明 |
|------|------|
| **セキュリティ** | 完全閉域環境で実行可能、インターネットアクセス不要 |
| **安定性** | 外部サービス依存なし、内部リソースのみで完結 |
| **起動速度** | Private Endpoint経由で高速なイメージ取得 |
| **バージョン管理** | タグで明示的にバージョン指定、環境の再現性を確保 |

#### ACR認証方式の選択

**Option 1: Managed Identity (推奨)**

```yaml
az container create \
  --image ${ACR_LOGIN_SERVER}/github-runner:latest \
  --acr-identity $MANAGED_IDENTITY_ID \
  --assign-identity $MANAGED_IDENTITY_ID \
  ...
```

**メリット**:
- ✅ パスワード管理不要
- ✅ 自動ローテーション
- ✅ 最高のセキュリティ

**前提条件**:
1. User-Assigned Managed Identityの作成
2. ACRへの`AcrPull`ロール割り当て

**セットアップ手順**:

```powershell
# 1. User-Assigned Managed Identity作成
$IDENTITY_NAME = "id-acr-pull-$ENV_NAME"
az identity create `
  --resource-group $RESOURCE_GROUP `
  --name $IDENTITY_NAME

# 2. Managed Identity IDを取得
$MANAGED_IDENTITY_ID = az identity show `
  --resource-group $RESOURCE_GROUP `
  --name $IDENTITY_NAME `
  --query id `
  --output tsv

# 3. ACRリソースIDを取得
$ACR_RESOURCE_ID = az acr show `
  --name $ACR_NAME `
  --query id `
  --output tsv

# 4. Managed IdentityにACR Pull権限を付与
az role assignment create `
  --assignee $MANAGED_IDENTITY_ID `
  --role "AcrPull" `
  --scope $ACR_RESOURCE_ID

# 5. GitHub Secretsに追加
gh secret set MANAGED_IDENTITY_ID --body $MANAGED_IDENTITY_ID
```

**Option 2: ACR Admin User (非推奨、テスト環境のみ)**

```yaml
az container create \
  --image ${ACR_LOGIN_SERVER}/github-runner:latest \
  --registry-login-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  ...
```

**デメリット**:
- ⚠️ パスワード管理が必要
- ⚠️ 定期的なローテーションが推奨
- ⚠️ 本番環境では非推奨

**使用条件**: ACR作成時に`enableAdminUser: true`を設定している場合のみ

#### ACRイメージのバージョン管理

**推奨タグ戦略**:

```powershell
# 開発環境: latestタグを使用（常に最新）
--image ${ACR_LOGIN_SERVER}/github-runner:latest

# 本番環境: 固定バージョンを使用（安定性重視）
--image ${ACR_LOGIN_SERVER}/github-runner:1.0.0
```

**イメージ更新フロー**:
1. Dockerfileを修正
2. ローカルでビルド
3. テスト
4. ACRにプッシュ（新バージョンタグ付与）
5. Workflowファイルでバージョン指定を更新

詳細は[Step 01: Azure Container Registry](../step01-container-registry/README.md)を参照してください。

### Job 1: setup-runner

#### 目的
Container InstanceでSelf-hosted Runnerを起動

#### 主要ステップ
1. **Azure Login**: サービスプリンシパルで認証
2. **Runner登録トークン取得**: GitHub APIから取得
3. **Container Instance作成**: vNet統合Subnetに配置
4. **Runner起動**: GitHub Actionsに登録

#### ポイント
- Runner名に `github.run_id` を使用してユニーク性確保
- vNet内Subnetに配置してPrivate Endpointアクセス可能
- Container起動後60秒待機でRunner準備完了

### Job 2: build-and-deploy

#### 目的
アプリケーションのビルドとデプロイ

#### 主要ステップ
1. **Checkout**: コード取得
2. **Azure Login**: Self-hosted Runner上で認証
3. **Key Vaultアクセス**: デプロイ用シークレット取得
4. **ビルド**: アプリケーションビルド
5. **デプロイ**: Web Appsへデプロイ

#### ポイント
- `runs-on: self-hosted` でvNet内Runnerを使用
- Key VaultへはPrivate Endpoint経由でアクセス
- Publish Profileを使用してデプロイ

### Job 3: cleanup

#### 目的
Runnerとリソースのクリーンアップ

#### 主要ステップ
1. **Runner削除**: GitHubからRunner登録解除
2. **Container削除**: Container Instanceを削除

#### ポイント
- `if: always()` で必ず実行
- `continue-on-error: true` でエラー時も継続
- コスト最適化のため即座に削除

## セキュリティベストプラクティス

### Secrets管理

#### DO
- ✅ すべてのシークレットをKey Vaultで管理
- ✅ GitHub Secretsは最小限（Key Vault接続情報のみ）
- ✅ `::add-mask::` でログにシークレットを出力しない

#### DON'T
- ❌ シークレットをWorkflowファイルにハードコード
- ❌ ログにシークレットを出力
- ❌ 不要な権限を付与

### ネットワークセキュリティ

- ✅ Self-hosted RunnerをvNet内に配置
- ✅ Private Endpoint経由でリソースアクセス
- ✅ NSGで通信制御

## トラブルシューティング

### Runner起動に失敗

**症状**: Container Instanceが起動しない

**確認事項**:
1. Subnet委任が正しく設定されているか
2. NSGでHTTPS (443)が許可されているか
3. GitHub PATが有効か

### デプロイに失敗

**症状**: Web Appsへのデプロイが失敗

**確認事項**:
1. Publish Profileが正しいか
2. Web AppsへのvNet経由アクセスが可能か
3. RunnerからWeb Appsへの通信が許可されているか

### Cleanupに失敗

**症状**: Container Instanceが削除されない

**対処法**:
```powershell
# 手動で削除
az container list --resource-group $RESOURCE_GROUP --output table
az container delete --resource-group $RESOURCE_GROUP --name <container-name> --yes
```

## コスト最適化

### Container Instances
- ジョブ完了後即座に削除
- 適切なCPU/メモリサイズ選定
- 同時実行数の制御

### 推奨設定
- **CPU**: 2 vCPU
- **メモリ**: 4 GB
- **実行時間**: 5〜10分/回

## 次のステップ

GitHub Actions Workflowが完成したら:

- [デプロイガイド](../../docs/deployment-guide.md)で全体の流れを確認
- 実際にデプロイを試す
- モニタリング設定を追加

## 参考リンク

- [GitHub Actions ドキュメント](https://docs.github.com/ja/actions)
- [Self-hosted runners](https://docs.github.com/ja/actions/hosting-your-own-runners)
- [Azure Web Apps デプロイ](https://learn.microsoft.com/ja-jp/azure/app-service/deploy-github-actions)
- [Azure Container Instances](https://learn.microsoft.com/ja-jp/azure/container-instances/)
