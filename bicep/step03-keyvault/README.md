# Step 03: Key Vaultの構築

このステップでは、デプロイ用認証情報を安全に管理するKey Vaultを構築します。

## 学習目標

このステップを完了すると、以下を理解できます:

- Key Vaultの作成と設定
- Private Endpoint経由のアクセス設定
- アクセスポリシーの設定
- シークレットの安全な管理方法

## 作成されるリソース

| リソース | 種類 | 目的 |
|---------|------|------|
| Key Vault | `Microsoft.KeyVault/vaults` | シークレット管理 |
| Private Endpoint | `Microsoft.Network/privateEndpoints` | セキュアなアクセス |
| Private DNS Zone | `Microsoft.Network/privateDnsZones` | 名前解決 |

## 前提条件

- Step 01, 02が完了していること
- 自分のオブジェクトIDを取得していること

### オブジェクトIDの取得

```powershell
# 現在のユーザーのオブジェクトIDを取得
az ad signed-in-user show --query id --output tsv
```

出力例: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

このIDをメモしておいてください。

## デプロイ手順

### 1. パラメータファイルの編集

`parameters.bicepparam` を開いて、`adminObjectId` を更新します:

```bicep
using './main.bicep'

param location = 'japaneast'
param environmentName = 'dev'
param vnetName = 'vnet-internal-rag-dev'
param keyVaultName = 'kv-gh-runner-dev'

// ここに自分のオブジェクトIDを設定
param adminObjectId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

**重要**: `keyVaultName` はAzure全体で一意である必要があります。

### 2. デプロイの実行

```powershell
# 環境変数の設定(Step 01で設定済みの場合はスキップ可)
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ENV_NAME = "dev"

# Step 03ディレクトリに移動
cd bicep/step03-keyvault

# デプロイ実行
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
```

**所要時間**: 約3-5分

### 3. デプロイ結果の確認

```powershell
# Key Vault確認
az keyvault show `
  --name kv-gh-runner-$ENV_NAME `
  --query "{Name:name, PublicNetworkAccess:properties.publicNetworkAccess, VaultUri:properties.vaultUri}"

# Private Endpoint確認
az network private-endpoint show `
  --resource-group $RESOURCE_GROUP `
  --name "pe-keyvault-$ENV_NAME" `
  --query "{Name:name, ProvisioningState:provisioningState}"
```

## シークレットの設定

### 重要: VPN接続時のDNS設定について

Key VaultはPrivate Endpoint経由でのみアクセス可能です。VPN接続している場合でも、ローカルPCから直接アクセスするには **DNS Private Resolver** の設定とVPN設定ファイルの編集が必要です。

#### VPN設定ファイルの編集

**ステップ1: DNS設定の確認**

まず、現在のDNS設定にKey Vault用のエントリがあるか確認します:

```powershell
# NRPTにKey Vaultのエントリがあるか確認
Get-DnsClientNrptPolicy | Where-Object {$_.Namespace -like "*.vault*"} | Format-Table -AutoSize

# エントリが無い場合は以下の手順でVPN設定を更新
```

**期待される結果**:
```
Namespace                NameServers
---------                -----------
.vault.azure.net         10.0.5.4
.vaultcore.azure.net     10.0.5.4
```

上記のエントリが**存在しない場合**は、以下の手順でVPN設定ファイルを編集してください。

**ステップ2: VPN設定ファイル（azurevpnconfig.xml）の編集**

1. VPN設定ファイルをテキストエディタで開きます
   - Azure VPN Clientを使用している場合: 設定をエクスポートして編集
   - 通常のVPN接続の場合: ダウンロードした`azurevpnconfig.xml`を編集

2. `<dnssuffixes>`セクションに以下の2行を追加:

```xml
<?xml version="1.0" encoding="utf-8"?>
<AzureVpnProfile>
  <clientconfig>
    <dnsservers>
      <dnsserver>10.0.5.4</dnsserver>
    </dnsservers>
  </clientconfig>
</AzureVpnProfile>
```

**ステップ3: VPN接続の再設定**

**Azure VPN Clientを使用している場合**:

1. Azure VPN Clientアプリを開く
2. 既存の接続を削除
3. 編集した`azurevpnconfig.xml`を再インポート
4. VPN接続を確立

**Windows標準VPN接続を使用している場合**:

```powershell
# 既存のVPN接続を削除
Remove-VpnConnection -Name "vnet-internal-rag-dev" -Force

# 編集したazurevpnconfig.xmlから再インポート
# （または新しい設定ファイルをダウンロードして再設定）
```

**ステップ4: 設定の確認**

VPN再接続後、設定が反映されたことを確認します:

```powershell
# DNSキャッシュをクリア
Clear-DnsClientCache

# NRPTにKey Vaultのエントリが追加されたか確認
Get-DnsClientNrptPolicy | Where-Object {$_.Namespace -like "*.vault*"} | Format-Table -AutoSize

# DNS解決テスト
nslookup kv-gh-runner-dev.vault.azure.net

# 期待される結果: 10.0.1.x (Private IP) が返される
```

#### DNS設定が未完了の場合の一時的な対処法

VPN設定の更新が完了するまでの間は、**Azure Cloud Shell**を使用してKey Vaultにアクセスできます:

```powershell
# Azure Portal → Cloud Shell (PowerShell) から実行
# Cloud ShellはAzure内部からアクセスするため、Private Endpoint経由で接続可能
```

> **💡 参考**: 詳細なVPN設定手順は [VPN接続セットアップガイド - Step 8 & Step 9](https://github.com/matakaha/internal_rag_step_by_step/blob/main/docs/vpn-setup-guide.md#step-8-azure-dns-private-resolver-%E3%81%AE%E4%BD%9C%E6%88%90) を参照してください。

### 1. 認証情報の格納

> **🔐 認証方式**: OIDC認証(推奨)とClient Secret方式で格納するシークレットが異なります。

#### OIDC認証方式の場合 (推奨)

[前提条件 - Azure サービスプリンシパルとFederated Credential作成](../../docs/00-prerequisites.md#3-azureサービスプリンシパルとfederated-credential作成)で作成した情報をKey Vaultに格納します。

```powershell
# Key Vault名
$KEY_VAULT_NAME = "kv-gh-runner-$ENV_NAME"

# OIDC認証に必要な情報を格納
# (前提条件で取得した$CLIENT_ID, $TENANT_ID, $SUBSCRIPTION_IDを使用)

# 変数が未定義の場合は、以下のコマンドで再取得できます:
# $CLIENT_ID = "<your-application-id>"
# $TENANT_ID = (az account show --query tenantId --output tsv)
# $SUBSCRIPTION_ID = (az account show --query id --output tsv)

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-CLIENT-ID" `
  --value $CLIENT_ID

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-TENANT-ID" `
  --value $TENANT_ID

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-SUBSCRIPTION-ID" `
  --value $SUBSCRIPTION_ID
```

> **💡 ヒント**: 
> - OIDC方式では**CLIENT_SECRET (パスワード)は不要**です
> - これらの変数は同じPowerShellセッションで保持されます
> - PowerShellセッションを閉じた場合は、変数が失われるため手動で再設定してください

#### Client Secret方式の場合 (非推奨)

<details>
<summary>Client Secret方式のシークレット格納手順</summary>

[前提条件 - Azure サービスプリンシパル作成](../../docs/00-prerequisites.md#3-azureサービスプリンシパルとfederated-credential作成)で作成したサービスプリンシパルの情報をKey Vaultに格納します。

```powershell
# Key Vault名
$KEY_VAULT_NAME = "kv-gh-runner-$ENV_NAME"

# サービスプリンシパル情報を格納
# (前提条件「3. Azure サービスプリンシパル作成」で取得した$CLIENT_ID, $CLIENT_SECRET, $TENANT_ID, $SUBSCRIPTION_IDを使用)

# 変数が未定義の場合は、以下のコマンドで再取得できます:
# $CLIENT_ID = "<appId-value>"
# $CLIENT_SECRET = "<password-value>"
# $TENANT_ID = "<tenant-value>"
# $SUBSCRIPTION_ID = (az account show --query id --output tsv)

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-CLIENT-ID" `
  --value $CLIENT_ID

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-CLIENT-SECRET" `
  --value $CLIENT_SECRET

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-TENANT-ID" `
  --value $TENANT_ID

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "AZURE-SUBSCRIPTION-ID" `
  --value $SUBSCRIPTION_ID
```

> **💡 ヒント**: 
> - 前提条件のコマンドで変数に格納済みの場合は、上記のように変数を使用できます
> - PowerShellセッションを閉じた場合は、変数が失われるため手動で再設定してください
> - 手動で値を設定する場合は、コメントアウトされた行のコメントを外して値を入力してください

</details>

### 2. Web Apps publish profileの格納（オプション）

```powershell
# Web Appsのpublish profileを一時ファイルに保存
az webapp deployment list-publishing-profiles `
  --resource-group $RESOURCE_GROUP `
  --name "app-internal-rag-$ENV_NAME" `
  --xml > publish-profile.xml

# ファイルからKey Vaultに格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "WEBAPP-PUBLISH-PROFILE" `
  --file publish-profile.xml

# 一時ファイルを削除
Remove-Item publish-profile.xml
```

> **💡 ヒント**: XMLファイルを直接`--value`で渡すとエラーになるため、`--file`オプションを使用します。

### 3. GitHub Personal Access Tokenの格納

[前提条件 - GitHub PAT作成](../../docs/00-prerequisites.md#2-github-pat作成)で取得したGitHub PATを格納します。

```powershell
# GitHub PATを変数に設定（前提条件で取得した値を入力）
$GITHUB_PAT = "<your-github-pat>"  # 例: "ghp_xxxxxxxxxxxxxxxxxxxx"

# Key VaultにGitHub PATを格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "GITHUB-PAT" `
  --value $GITHUB_PAT

Write-Host "GitHub PAT stored successfully in Key Vault" -ForegroundColor Green
```

> **💡 ヒント**: 
> - GitHub PATは、[前提条件のタスク2](../../docs/00-prerequisites.md#2-github-pat作成)で作成したPersonal Access Tokenです
> - `$GITHUB_PAT` 変数に値を設定してから Key Vault に格納することで、後続の Step 04 でも同じ変数を利用できます
> - PAT は `ghp_` で始まる形式です

### 4. Azure Container Registry (ACR) 認証情報の格納 (Step 01完了時)

[Step 01: Azure Container Registryの構築](../step01-container-registry/README.md)を完了している場合は、ACRからコンテナーイメージをプルするための認証情報を格納します。

#### 方法1: Managed Identity利用（推奨）

Container InstanceにManaged Identityを付与し、ACRへのプル権限を与える方式です。Key Vaultへのシークレット格納は**不要**です。

**手順はStep 04で実施します。**

#### 方法2: ACR Admin Userを利用（テスト・開発環境のみ）

<details>
<summary>Admin User方式の手順（本番環境非推奨）</summary>

ACR作成時に`enableAdminUser: true`を設定している場合のみ使用可能です。

```powershell
# ACR名を環境変数に設定
$ACR_NAME = "acrinternalrag$ENV_NAME"

# ACR管理者資格情報を取得
$ACR_USERNAME = az acr credential show --name $ACR_NAME --query username --output tsv
$ACR_PASSWORD = az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv

# Key Vaultに格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "ACR-USERNAME" `
  --value $ACR_USERNAME

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "ACR-PASSWORD" `
  --value $ACR_PASSWORD

# ACR Login Serverも格納（Workflow内で使用）
$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "ACR-LOGIN-SERVER" `
  --value $ACR_LOGIN_SERVER
```

> **⚠️ セキュリティ注意**: Admin User方式は管理が容易ですが、本番環境ではManaged Identity方式を強く推奨します。

</details>

#### 方法3: Service Principalを利用

<details>
<summary>Service Principal方式の手順</summary>

専用のService PrincipalにACRプル権限を付与する方式です。

```powershell
# ACR名とリソースIDを取得
$ACR_NAME = "acrinternalrag$ENV_NAME"
$ACR_RESOURCE_ID = az acr show --name $ACR_NAME --query id --output tsv

# Service Principal作成（ACR専用）
$SP_NAME = "sp-acr-pull-$ENV_NAME"
$SP_INFO = az ad sp create-for-rbac `
  --name $SP_NAME `
  --role "AcrPull" `
  --scope $ACR_RESOURCE_ID `
  --query "{appId:appId, password:password}" `
  --output json | ConvertFrom-Json

# Key Vaultに格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "ACR-SP-APP-ID" `
  --value $SP_INFO.appId

az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "ACR-SP-PASSWORD" `
  --value $SP_INFO.password

# ACR Login Serverも格納
$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer --output tsv
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "ACR-LOGIN-SERVER" `
  --value $ACR_LOGIN_SERVER
```

> **💡 推奨度**: Managed Identity > Service Principal > Admin User

</details>

### 5. シークレット一覧の確認

```powershell
# 格納されたシークレットを確認
az keyvault secret list `
  --vault-name $KEY_VAULT_NAME `
  --query "[].{Name:name, Enabled:attributes.enabled}" `
  --output table
```

**期待される出力**:

**OIDC認証方式 + ACR Managed Identity方式の場合**:
```
Name                      Enabled
------------------------  ---------
AZURE-CLIENT-ID           True
AZURE-TENANT-ID           True
AZURE-SUBSCRIPTION-ID     True
GITHUB-PAT                True
WEBAPP-PUBLISH-PROFILE    True (オプション)
```

**OIDC認証方式 + ACR Admin User方式の場合**:
```
Name                      Enabled
------------------------  ---------
AZURE-CLIENT-ID           True
AZURE-TENANT-ID           True
AZURE-SUBSCRIPTION-ID     True
GITHUB-PAT                True
WEBAPP-PUBLISH-PROFILE    True (オプション)
ACR-USERNAME              True
ACR-PASSWORD              True
ACR-LOGIN-SERVER          True
```

**Client Secret方式の場合**:
```
Name                      Enabled
------------------------  ---------
AZURE-CLIENT-ID           True
AZURE-CLIENT-SECRET       True
AZURE-TENANT-ID           True
AZURE-SUBSCRIPTION-ID     True
GITHUB-PAT                True
WEBAPP-PUBLISH-PROFILE    True (オプション)
```

## 詳細解説

### Key Vault設定

#### パブリックアクセス無効化

```bicep
publicNetworkAccess: 'Disabled'
networkAcls: {
  defaultAction: 'Deny'
  bypass: 'AzureServices'
}
```

**ポイント**:
- パブリックネットワークからのアクセスを完全に遮断
- Private Endpoint経由のみアクセス可能
- Azure信頼サービスは例外的に許可

#### ソフト削除と保護

```bicep
enableSoftDelete: true
softDeleteRetentionInDays: 90
enablePurgeProtection: true
```

**ポイント**:
- 誤削除時に90日間復旧可能
- Purge Protectionで完全削除を防止
- 本番環境では必須の設定

### アクセスポリシー

#### 管理者権限

```bicep
accessPolicies: [
  {
    objectId: adminObjectId
    permissions: {
      secrets: ['get', 'list', 'set', 'delete']
    }
  }
]
```

**ポイント**:
- デプロイ実行ユーザーに完全な権限を付与
- シークレットの作成・更新・削除が可能

#### Container Instance用権限（動的作成時に自動付与）

GitHub Actionsワークフローで動的に作成されるContainer Instanceには、必要に応じてManaged Identityとアクセス権限を付与できます。

## セキュリティベストプラクティス

### シークレット管理

#### DO
- ✅ すべての認証情報をKey Vaultで管理
- ✅ Private Endpoint経由のみアクセス
- ✅ 最小権限の原則を適用
- ✅ アクセスログを監視

#### DON'T
- ❌ シークレットをコードにハードコード
- ❌ GitHub Secretsに直接格納（Key Vault情報以外）
- ❌ パブリックアクセスを有効化
- ❌ 不要な権限を付与

### ローテーション戦略

#### 推奨スケジュール
- **サービスプリンシパル**: 3〜6ヶ月ごと
- **GitHub PAT**: 6〜12ヶ月ごと
- **その他APIキー**: サービス推奨に従う

#### ローテーション手順
1. 新しいシークレットを作成
2. Key Vaultに新しい値を設定
3. アプリケーションで動作確認
4. 古いシークレットを無効化
5. 一定期間後に削除

## 監視とアラート

### Key Vaultアクセスログ

```powershell
# 診断設定を有効化
az monitor diagnostic-settings create `
  --resource $(az keyvault show --name $KEY_VAULT_NAME --query id --output tsv) `
  --name keyvault-diagnostics `
  --workspace <log-analytics-workspace-id> `
  --logs '[{"category": "AuditEvent", "enabled": true}]' `
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

### アラート設定

重要なイベントに対するアラート:
- 未承認のアクセス試行
- シークレットの変更
- アクセス失敗の急増

## トラブルシューティング

### エラー: Key Vault名が既に使用されている

**原因**: Key Vault名はAzure全体で一意である必要がある

**対処法**:
```powershell
# 別の名前を試す
param keyVaultName = 'kv-gh-runner-dev-<ランダム文字列>'
```

### エラー: アクセス権限がない

**原因**: `adminObjectId` が正しくない

**対処法**:
```powershell
# オブジェクトIDを再確認
az ad signed-in-user show --query id --output tsv

# parameters.bicepparamを更新して再デプロイ
```

### エラー: Private Endpoint接続に失敗

**原因**: Subnet設定が正しくない

**対処法**:
```powershell
# Subnet確認
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name $VNET_NAME `
  --name snet-private-endpoints

# privateEndpointNetworkPoliciesがDisabledであることを確認
```

## コスト最適化

### Key Vault
- **Standard SKU**: 基本機能で十分
- **Premium SKU**: HSM保護が必要な場合のみ

### シークレット数
- 不要なシークレットは定期的に削除
- バージョン履歴の管理

### トランザクション
- キャッシュを活用してアクセス回数を削減
- バッチ処理で効率化

## 次のステップ

Key Vaultが完成したら、次のステップに進みましょう:

### オプション1: サンプルアプリケーションを使用（推奨）

📦 **[internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo)** - 実際に動作するRAGチャットアプリ

このサンプルリポジトリには、完全なアプリケーションコードとGitHub Actionsワークフローが含まれています。

### オプション2: 独自アプリケーションを開発

- [Step 02: Container Instance Subnetの追加](../step02-runner-subnet/README.md) - ACI用Subnet設定
- [Step 04: GitHub Actions Workflowの構築](../step04-github-actions/README.md) - Workflow設定の詳細
- [デプロイガイド](../../docs/deployment-guide.md) - 全体の流れ

## 参考リンク

- [Azure Key Vault のドキュメント](https://learn.microsoft.com/ja-jp/azure/key-vault/)
- [Key Vault のベスト プラクティス](https://learn.microsoft.com/ja-jp/azure/key-vault/general/best-practices)
- [シークレットについて](https://learn.microsoft.com/ja-jp/azure/key-vault/secrets/about-secrets)
- [Private Link を使用した Key Vault への接続](https://learn.microsoft.com/ja-jp/azure/key-vault/general/private-link-service)
