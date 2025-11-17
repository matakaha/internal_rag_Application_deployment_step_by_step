# デプロイガイド

このガイドでは、GitHub ActionsでAzure閉域環境（vNet統合済Web Apps）へCI/CDデプロイする環境を、Step by Stepで構築する方法を説明します。

## 前提条件の確認

開始前に、[前提条件](00-prerequisites.md)を満たしていることを確認してください。

### 必須環境

✅ [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)の環境が構築済み  
✅ Azure CLI、Bicep CLIがインストール済み  
✅ [前提条件ドキュメント - 事前準備タスク](00-prerequisites.md#事前準備タスク)を完了済み
  - 既存環境の確認
  - GitHub PAT作成
  - サービスプリンシパル作成

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

### Step 01: Azure Container Registryの構築

**学習内容**: ACR作成、Private Endpoint統合、Dockerイメージビルド、完全閉域環境でのコンテナー実行

> **💡 推奨理由**: 閉域環境でのセキュリティと安定性を確保するため、Container Instance起動時にインターネット経由でイメージをダウンロードするのではなく、事前にACRにビルドしたイメージを使用することを強く推奨します。

#### 1-1. ACRのデプロイ

```powershell
cd bicep/step01-container-registry

# パラメータファイルの確認・編集
notepad parameters.bicepparam
# acrName をグローバルで一意な名前に変更（例: acrinternalrag<会社名>dev）

# デプロイ
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# ACR名を環境変数に設定
$ACR_NAME = az deployment group show `
  --resource-group $RESOURCE_GROUP `
  --name main `
  --query properties.outputs.acrName.value `
  --output tsv

echo "ACR_NAME: $ACR_NAME"
```

#### 1-2. Runnerコンテナーイメージのビルドとプッシュ

```powershell
# パブリックアクセスを一時的に有効化（ローカルからプッシュするため）
az acr update --name $ACR_NAME --public-network-enabled true

# ACRにログイン
az acr login --name $ACR_NAME

# イメージをビルド
docker build -t "${ACR_NAME}.azurecr.io/github-runner:latest" .

# イメージをACRにプッシュ
docker push "${ACR_NAME}.azurecr.io/github-runner:latest"

# バージョンタグもプッシュ（推奨）
$VERSION = "1.0.0"
docker tag "${ACR_NAME}.azurecr.io/github-runner:latest" "${ACR_NAME}.azurecr.io/github-runner:${VERSION}"
docker push "${ACR_NAME}.azurecr.io/github-runner:${VERSION}"

# パブリックアクセスを無効化
az acr update --name $ACR_NAME --public-network-enabled false

# イメージ確認
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table
```

**所要時間**: 約10-15分（初回ビルド含む）

**詳細**: [Step 01 README](../bicep/step01-container-registry/README.md)

---

### Step 02: Container Instance Subnetの追加

**学習内容**: Self-hosted Runner用のSubnet作成、NSG設定、Container Instances委任

```powershell
cd bicep/step02-runner-subnet

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

**詳細**: [Step 02 README](../bicep/step02-runner-subnet/README.md)

---

### Step 03: Key Vaultの構築

**学習内容**: Key Vault作成、Private Endpoint統合、アクセスポリシー設定、シークレット管理

> ⚠️ **重要: VPN接続時のDNS設定について**
> 
> Key VaultはPrivate Endpoint経由でのみアクセス可能です。VPN接続からローカルPCで操作する場合、**DNS Private Resolverの設定**が必須です。
> 
> 📚 **別リポジトリ「[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)」の [VPN接続セットアップガイド](https://github.com/matakaha/internal_rag_step_by_step/blob/main/docs/vpn-setup-guide.md)** で説明されている **Step 8**（DNS Private Resolver作成）および **Step 9**（VPN クライアント構成ファイルのDNS設定）を完了してください。
> 
> **DNS設定が未完了の場合**は、[Step 03 README](../bicep/step03-keyvault/README.md#重要-vpn接続時のdns設定について) の「DNS設定が未完了の場合の対処法」を参照してください。

#### 3-1. オブジェクトIDの取得

```powershell
# 現在のユーザーのオブジェクトIDを取得
$OBJECT_ID = az ad signed-in-user show --query id --output tsv
echo "Your Object ID: $OBJECT_ID"
```

#### 3-2. パラメータファイルの編集

`bicep/step03-keyvault/parameters.bicepparam` を開いて、`adminObjectId` を設定:

```bicep
param adminObjectId = '<YOUR_OBJECT_ID>'
```

#### 3-3. デプロイ実行

```powershell
cd bicep/step03-keyvault

# デプロイ
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# デプロイ結果の確認
az keyvault show `
  --name "kv-gh-runner-$ENV_NAME" `
  --query "{Name:name, VaultUri:properties.vaultUri, PublicNetworkAccess:properties.publicNetworkAccess}"
```

#### 3-4. シークレットの設定

> **🔐 重要**: 認証方式によって格納するシークレットが異なります。

**OIDC認証方式の場合 (推奨)**:

```powershell
$KEY_VAULT_NAME = "kv-gh-runner-$ENV_NAME"

# OIDC認証用の情報を格納
# (前提条件「3. Azure サービスプリンシパルとFederated Credential作成」で取得した値を使用)
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-ID" --value $CLIENT_ID
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-TENANT-ID" --value $TENANT_ID
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-SUBSCRIPTION-ID" --value $SUBSCRIPTION_ID

# GitHub PATを格納
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "GITHUB-PAT" --value "<your-github-pat>"

# ACR認証情報を格納（Step 01完了時）
# Option 1: Managed Identity（推奨）- Key Vaultへの格納は不要
# → Step 04でManaged Identity作成とACRへの権限付与を実施

# Option 2: ACR Admin User（テスト環境のみ）
# $ACR_NAME = "acrinternalrag$ENV_NAME"
# $ACR_USERNAME = az acr credential show --name $ACR_NAME --query username --output tsv
# $ACR_PASSWORD = az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv
# $ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
# az keyvault secret set --vault-name $KEY_VAULT_NAME --name "ACR-USERNAME" --value $ACR_USERNAME
# az keyvault secret set --vault-name $KEY_VAULT_NAME --name "ACR-PASSWORD" --value $ACR_PASSWORD
# az keyvault secret set --vault-name $KEY_VAULT_NAME --name "ACR-LOGIN-SERVER" --value $ACR_LOGIN_SERVER

# シークレット確認
az keyvault secret list `
  --vault-name $KEY_VAULT_NAME `
  --query "[].name" `
  --output table
```

**従来のClient Secret方式の場合 (非推奨)**:

<details>
<summary>従来方式のシークレット格納手順</summary>

```powershell
$KEY_VAULT_NAME = "kv-gh-runner-$ENV_NAME"

# サービスプリンシパル情報を格納
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-ID" --value $CLIENT_ID
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-CLIENT-SECRET" --value $CLIENT_SECRET
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-TENANT-ID" --value $TENANT_ID
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "AZURE-SUBSCRIPTION-ID" --value $SUBSCRIPTION_ID

# GitHub PATを格納
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "GITHUB-PAT" --value "<your-github-pat>"

# シークレット確認
az keyvault secret list `
  --vault-name $KEY_VAULT_NAME `
  --query "[].name" `
  --output table
```

</details>

詳細な手順は **[Step 03 README - シークレットの設定](../bicep/step03-keyvault/README.md#シークレットの設定)** を参照してください。

**所要時間**: 約5-7分

**詳細**: [Step 03 README](../bicep/step03-keyvault/README.md)

---

### Step 04: GitHub Actions Workflowの構築

**学習内容**: GitHub Actions、Self-hosted Runner、CI/CDパイプライン、OIDC認証

> **📦 重要**: Step 04では、実際のアプリケーションコードとWorkflowファイルは [internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo) を使用することを推奨します。

> **🔐 認証方式の変更**: GitHub ActionsからAzureへの認証に**Federated Identity (OIDC)**を使用します。従来のClient Secret方式より安全で、長期的なシークレット管理が不要です。

#### 3-1. サンプルリポジトリを使用する場合（推奨）

1. **サンプルリポジトリをフォーク/クローン**
   ```powershell
   git clone https://github.com/matakaha/internal_rag_Application_sample_repo.git
   cd internal_rag_Application_sample_repo
   ```

2. **Federated Identityの設定とGitHub Secretsの設定**
   
   🔗 **[サンプルリポジトリ Step 04 - Federated Identity認証の設定](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step04-deploy-app.md#2-federated-identity-oidc-認証の設定)** を参照
   
   または
   
   🔗 **[Step 04 README - GitHub Secretsの設定](../bicep/step04-github-actions/README.md#2-github-secretsの設定)** を参照

3. **サンプルリポジトリのガイドに従う**
   - [Step 1: 環境準備](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step01-setup-environment.md)
   - [Step 4: アプリケーションデプロイ](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step04-deploy-app.md)

#### 3-2. 独自のリポジトリを使用する場合

独自のアプリケーションをデプロイする場合は、以下の手順で進めてください。

**リポジトリ準備**
```powershell
# 新しいリポジトリ作成
gh repo create <org>/<repo-name> --private
cd <your-app-repo>
```

**GitHub Secrets設定**

🔗 **[Step 04 README - GitHub Secretsの設定](../bicep/step04-github-actions/README.md#2-github-secretsの設定)** を参照

**Workflowファイル作成**

サンプルリポジトリの `.github/workflows/deploy.yml` を参考にしてください。
詳細は [Step 04 README - 参考: Workflowファイルの詳細解説](../bicep/step04-github-actions/README.md#📝-参考-workflowファイルの詳細解説) を参照してください。

**所要時間**: 約10-15分（初回デプロイ含む）

**詳細**: [Step 04 README](../bicep/step04-github-actions/README.md)

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
az keyvault show --name "kv-gh-runner-$ENV_NAME"

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
  --resource $(az keyvault show --name kv-gh-runner-$ENV_NAME --query id --output tsv) `
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
az keyvault delete --name "kv-gh-runner-$ENV_NAME"

# Key Vault完全削除（purge）
az keyvault purge --name "kv-gh-runner-$ENV_NAME"

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
