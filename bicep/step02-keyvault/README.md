# Step 02: Key Vaultの構築

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

- Step 01が完了していること
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
param keyVaultName = 'kv-deploy-dev'

// ここに自分のオブジェクトIDを設定
param adminObjectId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

**重要**: `keyVaultName` はAzure全体で一意である必要があります。

### 2. デプロイの実行

```powershell
# Step 02ディレクトリに移動
cd bicep/step02-keyvault

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
  --name kv-deploy-$ENV_NAME `
  --query "{Name:name, PublicNetworkAccess:properties.publicNetworkAccess, VaultUri:properties.vaultUri}"

# Private Endpoint確認
az network private-endpoint show `
  --resource-group $RESOURCE_GROUP `
  --name "pe-keyvault-$ENV_NAME" `
  --query "{Name:name, ProvisioningState:provisioningState}"
```

## シークレットの設定

### 1. サービスプリンシパル情報の格納

前提条件で作成したサービスプリンシパルの情報をKey Vaultに格納します。

```powershell
# Key Vault名
$KEY_VAULT_NAME = "kv-deploy-$ENV_NAME"

# サービスプリンシパル情報を格納
# (前提条件で取得したJSONから各値を設定)

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
```

### 2. Web Apps publish profileの格納（オプション）

```powershell
# Web Appsのpublish profileを取得
$PUBLISH_PROFILE = az webapp deployment list-publishing-profiles `
  --resource-group $RESOURCE_GROUP `
  --name "app-internal-rag-$ENV_NAME" `
  --xml

# Key Vaultに格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "WEBAPP-PUBLISH-PROFILE" `
  --value $PUBLISH_PROFILE
```

### 3. GitHub Personal Access Tokenの格納

```powershell
# GitHub PATを格納
az keyvault secret set `
  --vault-name $KEY_VAULT_NAME `
  --name "GITHUB-PAT" `
  --value "<your-github-pat>"
```

### 4. シークレット一覧の確認

```powershell
# 格納されたシークレットを確認
az keyvault secret list `
  --vault-name $KEY_VAULT_NAME `
  --query "[].{Name:name, Enabled:attributes.enabled}" `
  --output table
```

**期待される出力**:
```
Name                      Enabled
------------------------  ---------
AZURE-CLIENT-ID           True
AZURE-CLIENT-SECRET       True
AZURE-TENANT-ID           True
AZURE-SUBSCRIPTION-ID     True
GITHUB-PAT                True
WEBAPP-PUBLISH-PROFILE    True
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

#### Container Instance用権限（後で追加）

Step 03でContainer InstanceのマネージドIDに対して、シークレット取得権限を付与します。

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
param keyVaultName = 'kv-deploy-dev-<ランダム文字列>'
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

- [Step 03: GitHub Actions Workflowの構築](../step03-github-actions/README.md)
- [デプロイガイドに戻る](../../docs/deployment-guide.md)

## 参考リンク

- [Azure Key Vault のドキュメント](https://learn.microsoft.com/ja-jp/azure/key-vault/)
- [Key Vault のベスト プラクティス](https://learn.microsoft.com/ja-jp/azure/key-vault/general/best-practices)
- [シークレットについて](https://learn.microsoft.com/ja-jp/azure/key-vault/secrets/about-secrets)
- [Private Link を使用した Key Vault への接続](https://learn.microsoft.com/ja-jp/azure/key-vault/general/private-link-service)
