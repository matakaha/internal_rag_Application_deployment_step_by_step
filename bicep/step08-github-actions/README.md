# Step 08: GitHub Actions Workflow

このステップでは、GitHub Actionsを使って閉域Web AppsへCI/CDデプロイするワークフローを構築します。

## 学習目標

このステップを完了すると、以下を理解できます:

- Self-hosted RunnerをContainer Instanceで動的起動
- Key Vaultからのシークレット取得
- vNet内リソースへのデプロイ方法
- GitHub Actionsのベストプラクティス

## 作成されるファイル

| ファイル | 目的 |
|---------|------|
| `.github/workflows/deploy.yml` | メインデプロイワークフロー |
| `scripts/setup-runner.ps1` | Runner起動スクリプト |
| `scripts/cleanup-runner.ps1` | Runnerクリーンアップスクリプト |

## 前提条件

- Step 06, 07が完了していること
- GitHubリポジトリが作成済み
- GitHub Personal Access Token (PAT)が準備済み

## セットアップ手順

### 1. GitHubリポジトリの準備

#### リポジトリ作成

```bash
# GitHubでリポジトリを作成（Webまたはgh CLI）
gh repo create <org>/<repo-name> --private

# ローカルで初期化
git init
git remote add origin https://github.com/<org>/<repo-name>.git
```

#### ディレクトリ構造

```
your-app-repo/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── scripts/
│   ├── setup-runner.ps1
│   └── cleanup-runner.ps1
├── src/
│   └── (your application code)
└── README.md
```

### 2. GitHub Secretsの設定

#### 必要なSecrets

| Secret名 | 内容 | 取得方法 |
|---------|------|---------|
| `AZURE_CREDENTIALS` | サービスプリンシパル情報 | Step 07で格納したKey Vaultから |
| `KEY_VAULT_NAME` | Key Vault名 | `kv-deploy-<環境名>` |
| `GITHUB_PAT` | Personal Access Token | GitHub Settings |

#### Secretsの設定方法

```bash
# GitHub CLIを使用
gh secret set AZURE_CREDENTIALS < azure-credentials.json
gh secret set KEY_VAULT_NAME -b "kv-deploy-dev"
gh secret set GITHUB_PAT -b "<your-pat>"
```

または、GitHub Webから:
1. リポジトリの Settings → Secrets and variables → Actions
2. "New repository secret" をクリック
3. 各Secretを追加

### 3. Workflowファイルの作成

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

          # Container Instance作成
          az container create \
            --resource-group $RESOURCE_GROUP \
            --name $CONTAINER_GROUP_NAME \
            --image mcr.microsoft.com/azure-cli:latest \
            --vnet $VNET_NAME \
            --subnet $SUBNET_NAME \
            --location $LOCATION \
            --cpu 2 \
            --memory 4 \
            --restart-policy Never \
            --environment-variables \
              RUNNER_NAME=$RUNNER_NAME \
              RUNNER_TOKEN=$RUNNER_TOKEN \
              GITHUB_REPOSITORY=${{ github.repository }} \
            --command-line "/bin/bash -c 'curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz && tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz && ./config.sh --url https://github.com/${{ github.repository }} --token $RUNNER_TOKEN --name $RUNNER_NAME --work _work --labels self-hosted,azure,vnet && ./run.sh'"

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
