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

#### Docker Desktop (オプション)

ローカル環境でRunnerイメージをビルドする場合に必要です。

**ACR Tasksを使用する場合（推奨）は不要です。**

```powershell
# バージョン確認
docker --version

# 推奨: Docker Desktop 4.x 以上
```

**インストール方法**: 
- Windows: [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
- Mac: [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)
- Linux: [Docker Engine](https://docs.docker.com/engine/install/)

**代替手段**: Podman も使用可能

> **💡 Note**: Step 01では**ACR Tasks**（クラウド上でビルド）を推奨しています。ローカルDockerは不要です。ローカルでビルドしたい場合のみDocker Desktopをインストールしてください。

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
- Organization推奨(個人アカウントでも可)

#### GitHubリポジトリ

- デプロイ対象のアプリケーションコードを配置するリポジトリ
- GitHub Actionsが有効

確認方法:
```bash
# リポジトリにGitHub Actionsが有効か確認
# Settings → Actions → General → Actions permissionsを確認
```

#### Personal Access Token (PAT)

Self-hosted Runnerの登録に必要です。作成手順は[事前準備タスク - GitHub PAT作成](#2-github-pat作成)を参照してください。

> **⚠️ 重要**: トークンは生成後すぐにコピーしてください。再表示できません。

### 4. VPN接続とDNS設定

**Private Endpoint経由でKey VaultやWeb Appsにアクセスする場合、VPN接続とDNS設定が必須です。**

#### 必須設定

以下のガイドに従って、VPN接続環境を構築してください:

📚 **[VPN接続セットアップガイド](https://github.com/matakaha/internal_rag_step_by_step/blob/main/docs/vpn-setup-guide.md)**

特に重要なステップ:
- **Step 8**: Azure DNS Private Resolver の作成（10.0.5.4）
- **Step 9**: VPN クライアント構成ファイル（azurevpnconfig.xml）への DNS 設定追加

#### DNS設定確認コマンド

VPN接続後、DNS設定が正しく機能しているか確認:

```powershell
# NRPT (Name Resolution Policy Table) の確認
Get-DnsClientNrptPolicy | Format-Table -AutoSize

# DNS解決テスト（Key Vault用）
Resolve-DnsName "kv-gh-runner-$ENV_NAME.vault.azure.net"

# 期待される結果: 10.0.1.x のプライベートIPアドレスが返される
```

#### VPN設定が未完了の場合

VPN設定が完了していない場合は、以下の方法でリソースにアクセスできます:
- **Azure Cloud Shell**: Portal上のCloud Shellから操作
- **一時的なパブリックアクセス**: セキュリティリスクがあるため非推奨

詳細は[デプロイガイド - Step 02](deployment-guide.md#step-02-key-vaultの構築)を参照してください。

### 5. ローカル開発環境

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

#### GitHub CLI (オプション)

GitHub Secretsの設定を効率化できます（手動設定でも可）。

```powershell
# インストール確認
gh --version

# インストール方法（winget使用）
winget install --id GitHub.cli

# 認証
gh auth login
```

> **💡 ヒント**: GitHub CLIがない場合でも、GitHub Web UIから手動でSecretsを設定できます。詳細は[Step 05 - GitHub Secretsの設定](deployment-guide.md#step-05-github-actionsワークフローの構築)を参照してください。

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

Web Appsデプロイ用のサービスプリンシパルを作成します。

#### Azure CLI使用（推奨）

```powershell
# 環境変数の確認（事前準備タスク1で設定済みのはず）
$ENV_NAME = "dev"
$RESOURCE_GROUP = "rg-internal-rag-dev"

# サービスプリンシパル作成
$SP_NAME = "sp-github-actions-$ENV_NAME"
$SUBSCRIPTION_ID = (az account show --query id --output tsv)

$SP_OUTPUT = az ad sp create-for-rbac `
  --name $SP_NAME `
  --role contributor `
  --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP `
  | ConvertFrom-Json

# 出力された値を変数に保存（Step 02で使用）
$CLIENT_ID = $SP_OUTPUT.appId
$CLIENT_SECRET = $SP_OUTPUT.password
$TENANT_ID = $SP_OUTPUT.tenant

# 確認（パスワードは表示されません）
Write-Host "CLIENT_ID: $CLIENT_ID"
Write-Host "TENANT_ID: $TENANT_ID"
Write-Host "SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
Write-Host "CLIENT_SECRET: (保存済み - 表示されません)"
```

> **💡 ヒント**: これらの変数は同じPowerShellセッションで保持されます。Step 02のシークレット設定で使用します。

**出力例**:
```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName": "sp-github-actions-dev",
  "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

#### Managed Identity使用の前提条件

**AI SearchとStorage Account間の認証**:

サンプルアプリケーション([internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo))では、AI SearchからStorage Accountへのアクセスに**Managed Identity**を使用します。

```powershell
# AI SearchのManaged Identityを有効化
$SEARCH_SERVICE = "<your-search-service-name>"
az search service update `
    --resource-group $RESOURCE_GROUP `
    --name $SEARCH_SERVICE `
    --identity-type SystemAssigned

# AI SearchのManaged Identity(プリンシパルID)を取得
$SEARCH_PRINCIPAL_ID = az search service show `
    --resource-group $RESOURCE_GROUP `
    --name $SEARCH_SERVICE `
    --query identity.principalId -o tsv

# Storage Accountへのアクセス権限を付与
$STORAGE_ACCOUNT = "<your-storage-account-name>"
az role assignment create `
    --assignee $SEARCH_PRINCIPAL_ID `
    --role "Storage Blob Data Reader" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

Write-Host "AI Search Managed Identity configured successfully" -ForegroundColor Green
```

> **💡 ヒント**: Managed Identityを使用することで、Storage Accountのアクセスキーを管理する必要がなくなります。

#### Azureポータル使用（参考）

<details>
<summary>Azureポータルを使用したサービスプリンシパル作成手順（Azure CLIが使えない場合）</summary>

**ステップ1: アプリケーション登録**

1. [Azure Portal](https://portal.azure.com) にアクセス
2. **Microsoft Entra ID**（旧Azure Active Directory）を開く
3. 左メニューから **アプリの登録** を選択
4. **新規登録** をクリック
5. 以下を入力:
   - **名前**: `sp-github-actions-dev`（環境に応じて変更）
   - **サポートされているアカウントの種類**: 「この組織ディレクトリのみに含まれるアカウント」
   - **リダイレクトURI**: 空欄のまま
6. **登録** をクリック

**ステップ2: クライアントシークレットの作成**

1. 作成したアプリの **概要** ページで以下をメモ:
   - **アプリケーション (クライアント) ID** → `appId`
   - **ディレクトリ (テナント) ID** → `tenant`
2. 左メニューから **証明書とシークレット** を選択
3. **クライアント シークレット** タブで **新しいクライアント シークレット** をクリック
4. 以下を入力:
   - **説明**: `GitHub Actions deployment secret`
   - **有効期限**: 組織のポリシーに応じて選択（例: 180日、1年、2年）
5. **追加** をクリック
6. **値** 列に表示されたシークレットをすぐにコピー（`password`）

> **⚠️ 重要**: クライアントシークレットの値は、この画面を離れると二度と表示されません。必ずコピーしてください。

**ステップ3: ロールの割り当て**

1. Azureポータルで対象の **リソースグループ** を開く（例: `rg-internal-rag-dev`）
2. 左メニューから **アクセス制御 (IAM)** を選択
3. **追加** → **ロールの割り当ての追加** をクリック
4. **ロール** タブで **共同作成者** を選択し、**次へ**
5. **メンバー** タブで:
   - **アクセスの割り当て先**: 「ユーザー、グループ、またはサービス プリンシパル」
   - **選択** をクリックして、先ほど作成した `sp-github-actions-dev` を検索・選択
6. **レビューと割り当て** をクリック

**ステップ4: 必要な情報の確認**

以下の情報を取得できました:
- **Application (client) ID** (appId): Microsoft Entra IDのアプリ概要ページ
- **Client Secret** (password): 証明書とシークレットで生成した値
- **Directory (tenant) ID** (tenant): Microsoft Entra IDのアプリ概要ページ
- **Subscription ID**: サブスクリプション概要ページまたは以下のコマンドで取得
  ```powershell
  az account show --query id --output tsv
  ```

> **⚠️ 注意**: Client Secret方式はOIDC方式と比較してシークレット管理の負担が大きく、セキュリティリスクが高いため、OIDC方式を推奨します。

</details>

#### 取得した情報の保管

**OIDC方式の場合**:
- `CLIENT_ID` (Application ID)
- `TENANT_ID` (Directory ID)
- `SUBSCRIPTION_ID`

これらの3つの値を**GitHub Secrets**に設定します(Step 05で実施)。

**Client Secret方式の場合** (非推奨):
> **⚠️ 重要**: 
> - 出力された`appId`(Client ID)、`password`(Client Secret)、`tenant`(Tenant ID)、`subscriptionId`を安全に保管してください
> - `password`は一度しか表示されません。必ずコピーしてください
> - Step 02でこれらの4つの値をKey Vaultに格納します

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
