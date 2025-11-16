# 統合版: GitHub Actions デプロイ環境の一括構築

このディレクトリには、GitHub Actionsを使用した閉域Web Appsへのアプリケーションデプロイに必要なすべてのリソースを一括デプロイするBicepファイルが含まれています。

## 概要

Step 01-02を個別にデプロイする代わりに、このディレクトリの`main.bicep`を使用することで、すべてのリソースを一度にデプロイできます。

## 作成されるリソース

| カテゴリ | リソース | 説明 |
|---------|---------|------|
| **Networking** | Container Instance Subnet | Self-hosted Runner実行用のSubnet (10.0.6.0/24) |
| **Networking** | Network Security Group | Subnet用のセキュリティルール |
| **Security** | Key Vault | GitHub Actionsシークレット管理用 |
| **Security** | Private Endpoint | Key Vault用Private Endpoint |

## 前提条件

### 既存環境

このデプロイには、`internal_rag_step_by_step` で構築された以下のリソースが必要です:

- **VNet**: 10.0.0.0/16
- **Private Endpoint Subnet**: 10.0.1.0/24
- **Private DNS Zone**: `privatelink.vaultcore.azure.net`

### 必要な権限

- リソースグループへのContributor権限
- Key Vaultへのアクセス権限設定権限

### 必要なツール

- Azure CLI 2.50.0以降
- Bicep CLI

## デプロイ手順

### 1. パラメータファイルの編集

`parameters.bicepparam` を環境に合わせて編集します。

```powershell
# パラメータファイルを編集
code parameters.bicepparam
```

**重要な設定項目**:

- `environmentName`: 環境名 (dev, stg, prod)
- `vnetName`: 既存のVNet名
- `containerSubnetPrefix`: Container Instance Subnet用のアドレス範囲 (デフォルト: 10.0.6.0/24)
- `keyVaultName`: Key Vault名 (グローバルで一意)
- `adminObjectId`: 初期管理者のオブジェクトID

**オブジェクトIDの取得方法**:

```powershell
# 現在のユーザーのオブジェクトIDを取得
az ad signed-in-user show --query id -o tsv
```

### 2. デプロイの実行

```powershell
# 環境変数の設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$LOCATION = "japaneast"

# リソースグループの確認（既存のはず）
az group show --name $RESOURCE_GROUP

# デプロイの実行 (約10-15分かかります)
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
```

### 3. デプロイ結果の確認

```powershell
# Subnetの確認
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-dev" `
  --name "snet-container-instances" `
  --query "{name:name, addressPrefix:addressPrefix, delegations:delegations[0].serviceName}"

# Key Vaultの確認
az keyvault show `
  --name "kv-gh-runner-dev" `
  --resource-group $RESOURCE_GROUP `
  --query "{name:name, location:location, publicNetworkAccess:properties.publicNetworkAccess}"

# Private Endpointの確認
az network private-endpoint list `
  --resource-group $RESOURCE_GROUP `
  --query "[?contains(name, 'keyvault')].{name:name, subnet:subnet.id, connectionState:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}"
```

## メリット

### 時間の節約

- **ステップ版**: 各ステップを個別にデプロイ → 約15-20分
- **統合版**: 一度にデプロイ → 約10-15分

### 依存関係の自動管理

Bicepモジュールが自動的に依存関係を解決し、正しい順序でデプロイします。

### 一貫性の確保

すべてのリソースが同じパラメータセットで構築されるため、設定の不整合が発生しません。

## ステップ版との比較

| 項目 | ステップ版 (Step 01-02) | 統合版 (complete) |
|------|------------------------|-------------------|
| **用途** | 学習・段階的な理解 | 本番環境・効率重視 |
| **デプロイ時間** | 約15-20分 | 約10-15分 |
| **柔軟性** | 各ステップで調整可能 | パラメータで調整 |
| **トラブルシューティング** | ステップ単位で切り分け | モジュール単位で切り分け |

## トラブルシューティング

### Subnet アドレス範囲の競合

**エラー**: `AddressPrefix 10.0.6.0/24 overlaps with existing subnet`

**原因**: 指定したアドレス範囲が既存のSubnetと重複しています。

**対処法**:
1. 既存Subnetのアドレス範囲を確認:
   ```powershell
   az network vnet subnet list `
     --resource-group $RESOURCE_GROUP `
     --vnet-name "vnet-internal-rag-dev" `
     --query "[].{name:name, addressPrefix:addressPrefix}"
   ```
2. `parameters.bicepparam`の`containerSubnetPrefix`を変更
3. 例: `10.0.7.0/24`に変更

### Key Vault名の重複

**エラー**: `The vault name 'kv-gh-runner-dev' is already in use`

**原因**: Key Vault名がグローバルで一意でない、または削除後のソフトデリート期間中です。

**対処法**:
1. ソフトデリートされたKey Vaultを確認:
   ```powershell
   az keyvault list-deleted --query "[?name=='kv-gh-runner-dev']"
   ```
2. 削除されたKey Vaultを復旧または完全削除:
   ```powershell
   # 復旧する場合
   az keyvault recover --name "kv-gh-runner-dev"
   
   # 完全削除する場合（慎重に）
   az keyvault purge --name "kv-gh-runner-dev"
   ```
3. または、`parameters.bicepparam`の`keyVaultName`を別の名前に変更

### adminObjectId が無効

**エラー**: `The principal with objectId 'xxx' does not exist in the directory`

**対処法**:
1. 正しいオブジェクトIDを取得:
   ```powershell
   az ad signed-in-user show --query id -o tsv
   ```
2. `parameters.bicepparam`の`adminObjectId`を更新

## 次のステップ

デプロイが完了したら:

### 1. GitHub Secretsの設定

🔗 **[Step 03 - GitHub Secretsの設定](../step03-github-actions/README.md#2-github-secretsの設定)**

Key Vaultから取得した値を使って、以下の3つのGitHub Secretsを設定します:
- `AZURE_CREDENTIALS`
- `KEY_VAULT_NAME`
- `GH_PAT`

### 2. アプリケーションのデプロイ

以下の2つのオプションがあります:

#### オプション1: サンプルアプリケーションを使用（推奨）

📦 **[internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo)**

完全に動作するRAGチャットアプリケーションとGitHub Actionsワークフローが含まれています。
- [Step 1: 環境準備](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step01-setup-environment.md)
- [Step 4: アプリケーションデプロイ](https://github.com/matakaha/internal_rag_Application_sample_repo/blob/main/docs/step04-deploy-app.md)

#### オプション2: 独自アプリケーションを開発

独自のアプリケーションをデプロイする場合は、以下を参照してください:
- [Step 03: GitHub Actionsワークフロー](../step03-github-actions/README.md) - Workflow設定の詳細
- [参考: Workflowファイルの詳細解説](../step03-github-actions/README.md#📝-参考-workflowファイルの詳細解説)

## クリーンアップ

統合版でデプロイしたリソースを削除する場合:

```powershell
# Key Vaultの削除（シークレットを含む）
az keyvault delete `
  --name "kv-gh-runner-dev" `
  --resource-group $RESOURCE_GROUP

# Subnetの削除（NSGも一緒に削除される）
az network vnet subnet delete `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-dev" `
  --name "snet-container-instances"

# Private Endpointの削除
az network private-endpoint delete `
  --resource-group $RESOURCE_GROUP `
  --name "pe-keyvault-dev"
```

**注意**: Key Vaultは削除後もソフトデリート状態で90日間保持されます。完全削除するには`az keyvault purge`を使用してください。

## 参考資料

- [Step 01: Runner Subnetの構築](../step01-runner-subnet/README.md)
- [Step 02: Key Vaultの構築](../step02-keyvault/README.md)
- [Step 03: GitHub Actionsワークフロー](../step03-github-actions/README.md)
- [Azure Container Instances](https://learn.microsoft.com/azure/container-instances/)
- [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/)
- [GitHub Actions Self-hosted Runners](https://docs.github.com/actions/hosting-your-own-runners)
