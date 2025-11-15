# デプロイガイド

このガイドでは、GitHub ActionsでAzure閉域環境（vNet統合済Web Apps）へCI/CDデプロイする環境を、Step by Stepで構築する方法を説明します。

## 前提条件の確認

開始前に、[前提条件](00-prerequisites.md)を満たしていることを確認してください。

### 必須環境

✅ [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)の環境が構築済み  
✅ Azure CLI、Bicep CLIがインストール済み  
✅ GitHubアカウント、リポジトリが準備済み  
✅ GitHub Personal Access Token (PAT)を取得済み  
✅ サービスプリンシパルを作成済み

## デプロイ方法の選択

### オプション1: ステップバイステップデプロイ（推奨）

各ステップを順番にデプロイし、学びながら構築します。

**メリット**:
- 各コンポーネントの役割を理解できる
- 問題が発生した際の切り分けが容易
- 段階的に学習できる

**デプロイ時間**: 約30-45分

### オプション2: 統合デプロイ

全ステップを一括でデプロイします（本ガイドでは未実装）。

## ステップバイステップデプロイ

### 準備

1. **リポジトリのクローン**

```powershell
git clone https://github.com/matakaha/internal_rag_Application_deployment_step_by_step.git
cd internal_rag_Application_deployment_step_by_step
```

2. **Azure CLIでログイン**

```powershell
az login
az account set --subscription "<your-subscription-id>"
```

3. **環境変数の設定**

```powershell
# リソースグループ名（既存）
$RESOURCE_GROUP = "rg-internal-rag-dev"
# デプロイ先リージョン
$LOCATION = "japaneast"
# 環境名
$ENV_NAME = "dev"

# 既存環境の確認
az network vnet show `
  --resource-group $RESOURCE_GROUP `
  --name "vnet-internal-rag-$ENV_NAME" `
  --query name
```

### Step 01: Container Instance Subnet追加

**学習内容**: Self-hosted Runner用のSubnet、NSG設定

```powershell
cd bicep/step01-runner-subnet

# パラメータファイルの確認・編集
notepad parameters.bicepparam

# デプロイ
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# デプロイ結果の確認
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances `
  --query "{Name:name, AddressPrefix:addressPrefix, Delegations:delegations[].serviceName}"
```

**所要時間**: 約2-3分

**詳細**: [Step 01 README](../bicep/step01-runner-subnet/README.md)

---

### Step 02: Key Vaultの構築

**学習内容**: Key Vault、Private Endpoint、アクセスポリシー、シークレット管理

#### 7-1. オブジェクトIDの取得

```powershell
# 現在のユーザーのオブジェクトIDを取得
$OBJECT_ID = az ad signed-in-user show --query id --output tsv
echo "Your Object ID: $OBJECT_ID"
```

#### 7-2. パラメータファイルの編集

`bicep/step02-keyvault/parameters.bicepparam` を開いて、`adminObjectId` を設定:

```bicep
param adminObjectId = '<YOUR_OBJECT_ID>'
```

#### 7-3. デプロイ実行

```powershell
cd ../step02-keyvault

# デプロイ
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# デプロイ結果の確認
az keyvault show `
  --name "kv-deploy-$ENV_NAME" `
  --query "{Name:name, VaultUri:properties.vaultUri, PublicNetworkAccess:properties.publicNetworkAccess}"
```

#### 7-4. シークレットの設定

```powershell
$KEY_VAULT_NAME = "kv-deploy-$ENV_NAME"

# サービスプリンシパル情報を格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-CLIENT-ID" `
  --value "<your-client-id>"

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-CLIENT-SECRET" `
  --value "<your-client-secret>"

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-TENANT-ID" `
  --value "<your-tenant-id>"

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-SUBSCRIPTION-ID" `
  --value "<your-subscription-id>"

# GitHub PATを格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "GITHUB-PAT" `
  --value "<your-github-pat>"

# Web Apps publish profile取得・格納
az webapp deployment list-publishing-profiles `
  --resource-group $RESOURCE_GROUP `
  --name "app-internal-rag-$ENV_NAME" `
  --xml | az keyvault secret set `
    --vault-name $KEY_VAULT_NAME `
    --name "WEBAPP-PUBLISH-PROFILE" `
    --file /dev/stdin

# シークレット確認
az keyvault secret list `
  --vault-name $KEY_VAULT_NAME `
  --query "[].name" `
  --output table
```

**所要時間**: 約5-7分

**詳細**: [Step 02 README](../bicep/step02-keyvault/README.md)

---

### Step 03: GitHub Actions Workflowの構築

**学習内容**: GitHub Actions、Self-hosted Runner、CI/CDパイプライン

#### 8-1. アプリケーションリポジトリの準備

```powershell
# 新しいリポジトリ作成（GitHub Web or gh CLI）
gh repo create <org>/<repo-name> --private

# または既存リポジトリを使用
cd <your-app-repo>
```

#### 8-2. Workflowファイルの配置

```powershell
# ディレクトリ作成
mkdir -p .github/workflows

# Workflowファイルをコピー
# Step 03 READMEからworkflow例をコピーして配置
notepad .github/workflows/deploy.yml
```

#### 8-3. GitHub Secretsの設定

```powershell
# サービスプリンシパル情報をJSONファイルに保存
@"
{
  "clientId": "<client-id>",
  "clientSecret": "<client-secret>",
  "subscriptionId": "<subscription-id>",
  "tenantId": "<tenant-id>"
}
"@ | Out-File -FilePath azure-credentials.json -Encoding utf8

# GitHub Secretsに設定
gh secret set AZURE_CREDENTIALS < azure-credentials.json
gh secret set KEY_VAULT_NAME -b "kv-deploy-$ENV_NAME"
gh secret set GITHUB_PAT -b "<your-github-pat>"

# ファイル削除（セキュリティ）
Remove-Item azure-credentials.json
```

または、GitHub Web UIから:
1. リポジトリ → Settings → Secrets and variables → Actions
2. "New repository secret" で各Secretを追加

#### 8-4. 初回デプロイ実行

```powershell
# コミット・プッシュ
git add .
git commit -m "Add GitHub Actions workflow"
git push origin main

# GitHub Actionsタブでワークフロー実行を確認
```

**所要時間**: 約10-15分（初回デプロイ含む）

**詳細**: [Step 03 README](../bicep/step03-github-actions/README.md)

---

### デプロイ完了の確認

```powershell
# 全リソースの確認
az resource list `
  --resource-group $RESOURCE_GROUP `
  --query "[?contains(name, '$ENV_NAME')].{Name:name, Type:type, Location:location}" `
  --output table

# 新規追加されたSubnetの確認
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances

# Key Vaultの確認
az keyvault show --name "kv-deploy-$ENV_NAME"

# GitHub Actionsワークフロー実行履歴の確認
gh run list --repo <org>/<repo-name>
```

## トラブルシューティング

### Subnet作成エラー

**エラー**: `Subnet address space overlaps`

**対処法**:
- `parameters.bicepparam` の `containerSubnetPrefix` を変更
- 既存Subnetと重複しないアドレス範囲を指定

### Key Vault作成エラー

**エラー**: `The vault name is already in use`

**対処法**:
- Key Vault名はAzure全体で一意
- `parameters.bicepparam` の `keyVaultName` を変更

### Runner起動エラー

**エラー**: Container Instanceが起動しない

**確認事項**:
1. Subnet委任が正しく設定されているか
2. NSGでHTTPS (443)が許可されているか
3. GitHub PATが有効か

**デバッグ方法**:
```powershell
# Container Instance ログ確認
az container logs `
  --resource-group $RESOURCE_GROUP `
  --name <container-name>
```

### デプロイ失敗

**エラー**: Web Appsへのデプロイが失敗

**確認事項**:
1. Publish Profileが正しいか
2. Web AppsへのvNet経由アクセスが可能か
3. RunnerからWeb Appsへの通信が許可されているか

## モニタリング設定

### Container Instancesのログ

```powershell
# 診断設定を有効化
az monitor diagnostic-settings create `
  --resource <container-instance-id> `
  --name aci-diagnostics `
  --workspace <log-analytics-workspace-id> `
  --logs '[{"category": "ContainerInstanceLog", "enabled": true}]'
```

### Key Vaultの監査ログ

```powershell
# 診断設定を有効化
az monitor diagnostic-settings create `
  --resource $(az keyvault show --name kv-deploy-$ENV_NAME --query id --output tsv) `
  --name keyvault-diagnostics `
  --workspace <log-analytics-workspace-id> `
  --logs '[{"category": "AuditEvent", "enabled": true}]'
```

### GitHub Actionsの実行履歴

```bash
# CLI で確認
gh run list --repo <org>/<repo-name>
gh run view <run-id> --log
```

## リソースのクリーンアップ

### 個別リソースの削除

```powershell
# Container Instance削除
az container delete `
  --resource-group $RESOURCE_GROUP `
  --name <container-name> `
  --yes

# Key Vault削除（ソフト削除有効）
az keyvault delete --name "kv-deploy-$ENV_NAME"

# Key Vault完全削除（purge）
az keyvault purge --name "kv-deploy-$ENV_NAME"

# Subnet削除（他リソースが依存している場合は削除不可）
az network vnet subnet delete `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances
```

### リソースグループ全体の削除

```powershell
# 警告: 既存のinternal_rag環境も含めて全削除されます
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

> **⚠️ 注意**: リソースグループを削除すると、internal_rag_step_by_stepで作成したリソースも削除されます。

## ベストプラクティス

### インフラストラクチャ
- ✅ すべてのインフラをBicepで管理
- ✅ パラメータファイルで環境ごとに分離
- ✅ タグを活用してリソース管理

### セキュリティ
- ✅ すべてのシークレットをKey Vaultで管理
- ✅ Private Endpoint経由でアクセス
- ✅ NSGで通信制御
- ✅ 最小権限の原則を適用

### CI/CD
- ✅ mainブランチ保護を有効化
- ✅ Pull Requestによるレビュー
- ✅ 自動テストの実行
- ✅ デプロイ前の承認フロー

### コスト管理
- ✅ Container Instancesの都度起動・削除
- ✅ 不要なリソースの削除
- ✅ コストアラートの設定

## 次のステップ

### 環境の拡張

1. **複数環境対応**
   - Dev、Staging、Production環境を分離
   - 環境ごとのパラメータファイル作成

2. **監視・アラート強化**
   - Application Insightsの設定
   - Log Analytics統合
   - Azure Monitorアラート

3. **自動化強化**
   - シークレットの自動ローテーション
   - Logic Apps統合
   - Azure Automation活用

### 学習リソース

- [GitHub Actions ドキュメント](https://docs.github.com/ja/actions)
- [Azure Key Vault ベストプラクティス](https://learn.microsoft.com/ja-jp/azure/key-vault/general/best-practices)
- [Azure Container Instances](https://learn.microsoft.com/ja-jp/azure/container-instances/)
- [Azure App Service CI/CD](https://learn.microsoft.com/ja-jp/azure/app-service/deploy-continuous-deployment)

## サポート

問題が発生した場合:
1. [トラブルシューティングセクション](#トラブルシューティング)を確認
2. [Issues](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/issues)で検索
3. 新しいIssueを作成

## まとめ

このガイドでは、以下を学習しました:

✅ Self-hosted Runner用環境の構築  
✅ Key Vaultによるシークレット管理  
✅ GitHub Actionsを使ったCI/CD構築  
✅ 閉域環境へのセキュアなデプロイ方法  

これらの知識を活用して、本番環境でも安全かつ効率的なCI/CDパイプラインを構築できます。
