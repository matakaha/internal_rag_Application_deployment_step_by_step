# 前提条件

このガイドを開始する前に、以下の前提条件を満たしていることを確認してください。

## 必須環境

### 1. 既存のAzure閉域環境

このガイドは、[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)で構築した環境が**既に存在する**ことを前提としています。

#### 必要なリソース

| リソース | 確認方法 |
|---------|---------|
| **Virtual Network** | `az network vnet show --resource-group <RG名> --name vnet-internal-rag-<環境名>` |
| **Subnets** | `az network vnet subnet list --resource-group <RG名> --vnet-name vnet-internal-rag-<環境名>` |
| **Web Apps** | `az webapp show --resource-group <RG名> --name app-internal-rag-<環境名>` |
| **Private DNS Zones** | `az network private-dns zone list --resource-group <RG名>` |

#### 確認コマンド

```powershell
# 環境変数設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ENV_NAME = "dev"

# Virtual Network確認
az network vnet show `
  --resource-group $RESOURCE_GROUP `
  --name "vnet-internal-rag-$ENV_NAME" `
  --query "{name:name, addressSpace:addressSpace.addressPrefixes}"

# Subnet確認
az network vnet subnet list `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --output table

# Web Apps確認
az webapp show `
  --resource-group $RESOURCE_GROUP `
  --name "app-internal-rag-$ENV_NAME" `
  --query "{name:name, state:state, vnetRouteAllEnabled:vnetRouteAllEnabled}"
```

**期待される出力**:
- Virtual Networkが存在し、アドレス空間が `10.0.0.0/16`
- 以下のSubnetが存在:
  - `snet-private-endpoints` (10.0.1.0/24)
  - `snet-app-integration` (10.0.2.0/24)
  - `snet-compute` (10.0.3.0/24)
- Web AppsがvNet統合済 (`vnetRouteAllEnabled: true`)

### 2. Azure環境

#### Azure CLI

```powershell
# バージョン確認
az --version

# 2.50.0以上を推奨
```

インストール方法: [Azure CLI のインストール](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)

#### Bicep CLI

```powershell
# バージョン確認
az bicep version

# 最新版を推奨
az bicep upgrade
```

#### Azure サブスクリプション

必要な権限:
- **共同作成者** または **所有者** ロール
- Key Vault管理者権限
- Container Instance作成権限

確認方法:
```powershell
# サブスクリプション確認
az account show --query "{name:name, id:id, state:state}"

# 権限確認
az role assignment list --assignee <your-email> --output table
```

### 3. GitHub環境

#### GitHubアカウント

- GitHubアカウントが必要
- Organization推奨（個人アカウントでも可）

#### GitHubリポジトリ

- デプロイ対象のアプリケーションコードを配置するリポジトリ
- GitHub Actionsが有効

確認方法:
```bash
# リポジトリにGitHub Actionsが有効か確認
# Settings → Actions → General → Actions permissionsを確認
```

#### Personal Access Token (PAT)

Self-hosted Runnerの登録に必要:

1. GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" をクリック
3. 以下のスコープを選択:
   - `repo` (フルアクセス)
   - `workflow`
   - `admin:org` (Organizationの場合)
4. トークンを生成してコピー（後で使用）

> **⚠️ 重要**: トークンは生成後すぐにコピーしてください。再表示できません。

### 4. ローカル開発環境

#### PowerShell

```powershell
# バージョン確認
$PSVersionTable.PSVersion

# 5.1以上または PowerShell Core 7.x推奨
```

#### Git

```powershell
# バージョン確認
git --version

# 2.30.0以上を推奨
```

## ネットワーク設計の考慮事項

### IPアドレス範囲

既存の環境:
- **VNet**: 10.0.0.0/16
- **Private Endpoint Subnet**: 10.0.1.0/24
- **App Integration Subnet**: 10.0.2.0/24
- **Compute Subnet**: 10.0.3.0/24
- **Gateway Subnet**: 10.0.4.0/24 (VPN Gateway用、オプション)
- **DNS Resolver Subnet**: 10.0.5.0/28 (DNS Private Resolver用、オプション)

新規追加:
- **Container Instance Subnet**: 10.0.6.0/24 (新規作成)

> **💡 ヒント**: 
> - 10.0.4.0/24: VPN Gateway用（オプション）
> - 10.0.5.0/28: DNS Private Resolver用（オプション）
> - 10.0.7.0/24以降: 将来の拡張用に予約

### DNS設定

既存のPrivate DNS Zones:
- `privatelink.blob.core.windows.net`
- `privatelink.api.azureml.ms`
- `privatelink.notebooks.azure.net`
- `privatelink.search.windows.net`
- `privatelink.azurewebsites.net`

新規追加:
- `privatelink.vaultcore.azure.net` (Key Vault用)

## コスト見積もり

### 既存環境のコスト

既存環境（internal_rag_step_by_step）のコストは含まれません。

### 新規追加リソースのコスト

| リソース | SKU/構成 | 月額概算 (円) | 備考 |
|---------|---------|--------------|------|
| **Key Vault** | Standard | ¥500 | シークレット数に応じて増加 |
| **Container Instances** | 1vCPU/1.5GB | ¥1,000〜3,000 | デプロイ頻度による |
| **Private Endpoint** | 2個追加 | ¥2,000 | Key Vault用 |
| **NSG** | - | 無料 | - |
| **データ転送** | - | ¥500〜1,000 | vNet内通信 |

**月額合計概算**: **¥4,000〜7,000**

> **💡 コスト最適化のヒント**:
> - Container Instancesは使用時のみ課金（都度起動・削除）
> - デプロイ頻度を調整してコスト管理
> - 不要なシークレットは定期的に削除

### Container Instancesのコスト詳細

**料金計算例** (1vCPU / 1.5GB メモリ):
- 1時間あたり: 約¥10
- デプロイ1回あたりの稼働時間: 約5〜10分
- デプロイ1回あたりのコスト: 約¥1〜2

**月間デプロイ回数とコスト**:
| デプロイ回数/月 | 月額コスト概算 |
|---------------|--------------|
| 50回 | ¥50〜100 |
| 100回 | ¥100〜200 |
| 500回 | ¥500〜1,000 |
| 1,000回 | ¥1,000〜2,000 |

## 事前準備タスク

### 1. 既存環境の確認

```powershell
# スクリプトで一括確認
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ENV_NAME = "dev"

Write-Host "=== Virtual Network ===" -ForegroundColor Green
az network vnet show --resource-group $RESOURCE_GROUP --name "vnet-internal-rag-$ENV_NAME" --query name

Write-Host "`n=== Subnets ===" -ForegroundColor Green
az network vnet subnet list --resource-group $RESOURCE_GROUP --vnet-name "vnet-internal-rag-$ENV_NAME" --query "[].{Name:name, AddressPrefix:addressPrefix}" --output table

Write-Host "`n=== Web Apps ===" -ForegroundColor Green
az webapp show --resource-group $RESOURCE_GROUP --name "app-internal-rag-$ENV_NAME" --query "{Name:name, State:state, VnetIntegrated:vnetRouteAllEnabled}"

Write-Host "`n=== Private DNS Zones ===" -ForegroundColor Green
az network private-dns zone list --resource-group $RESOURCE_GROUP --query "[].name" --output table
```

### 2. GitHub PAT作成

1. https://github.com/settings/tokens にアクセス
2. "Generate new token (classic)" をクリック
3. 必要なスコープを選択:
   - `repo`
   - `workflow`
   - `admin:org` (Organization使用時)
4. トークンをコピーして安全に保管

### 3. Azure サービスプリンシパル作成

Web Appsデプロイ用のサービスプリンシパルを作成:

```powershell
# サービスプリンシパル作成
$SP_NAME = "sp-github-actions-$ENV_NAME"
$SUBSCRIPTION_ID = (az account show --query id --output tsv)

az ad sp create-for-rbac `
  --name $SP_NAME `
  --role contributor `
  --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP `
  --sdk-auth

# 出力されたJSONを保存（後でKey Vaultに格納）
```

**出力例**:
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

> **⚠️ 重要**: このJSONは安全に保管してください。Step 02でKey Vaultに格納します。

## トラブルシューティング

### 既存環境が見つからない

**エラー**: `ERROR: Resource 'vnet-internal-rag-dev' not found`

**対処法**:
1. [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)のREADMEに従って環境を構築
2. リソースグループ名・環境名が正しいか確認

### Azure CLIの権限不足

**エラー**: `ERROR: The client does not have authorization to perform action`

**対処法**:
1. サブスクリプションの共同作成者権限を確認
2. 管理者に権限付与を依頼

### GitHub PAT作成エラー

**エラー**: スコープ選択画面が表示されない

**対処法**:
1. Personal access tokens (classic)を使用しているか確認
2. Fine-grained tokensではなくClassicを選択

## 次のステップ

前提条件を満たしたら、次のドキュメントに進んでください:

- [アーキテクチャ概要](01-architecture.md)
- [デプロイガイド](deployment-guide.md)

## サポート

問題が解決しない場合:
1. [FAQ](faq.md) を確認
2. [Issues](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/issues) で検索
3. 新しいIssueを作成
