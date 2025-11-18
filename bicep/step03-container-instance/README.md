# Step 03: GitHub Actions Self-hosted Runner (Container Instance)の構築

このステップでは、GitHub Actions Self-hosted Runner用のAzure Container Instanceを**事前に作成**します。

## 学習目標

このステップを完了すると、以下を理解できます:

- Azure Container Instanceの作成とvNet統合
- ACRからのイメージプル(Private Endpoint経由)
- Managed Identityを使用したACR認証
- GitHub Actions Self-hosted Runnerの事前準備

## なぜ事前にACIを作成するのか?

GitHub Actions Self-hosted Runnerを使用するために、Azure Container Instance (ACI)を事前に作成します。

### このアプローチの重要性

GitHub Actionsのワークフロー実行中にACIを作成しようとすると、以下の問題が発生します:

1. **ACRへのアクセス問題**: GitHub Actions(ubuntu-latest runner)はインターネット上で動作するため、ACRからRunnerイメージをプルするにはACRをパブリックアクセス可能にする必要があります
2. **セキュリティリスク**: ACRのパブリック公開は、完全閉域構成を目指す本アーキテクチャの方針に反します
3. **運用の複雑さ**: デプロイごとにACRのアクセス設定を変更する必要があります

### 事前作成のメリット

ACIを**事前に作成**しておくことで、これらの問題を解決できます:

✅ **完全閉域を維持**: ACIとACRは同じvNet内にあるため、Private Endpoint経由でイメージをプルできます  
✅ **シンプルな運用**: GitHub Actionsワークフローでは、作成済みのACIを起動・停止するだけでOKです  
✅ **セキュリティ強化**: ACRへのパブリックアクセスが不要になり、完全閉域構成を実現できます

### アーキテクチャの流れ

```
[事前準備フェーズ(このステップで実施)]
Azure Container Instance
  ← ACRからRunnerイメージをプル (Private Endpoint経由)
  ← Managed Identityで認証

[GitHub Actions実行フェーズ(Step 05で実施)]
GitHub Actions (ubuntu-latest)
  ↓ ACIを起動 (az container start)
  ↓ ワークフローを実行
  ↓ ACIを停止 (az container stop)
```

## 作成されるリソース

| リソース | 種類 | 目的 |
|---------|------|------|
| Container Instance | `Microsoft.ContainerInstance/containerGroups` | GitHub Actions Self-hosted Runner |
| Managed Identity | `SystemAssigned` | ACRへの認証 |
| Role Assignment | `AcrPull` | ACRからのイメージプル権限 |

## 前提条件

- [Step 01: ACRの構築](../step01-container-registry/README.md)が完了していること
- [Step 02: Container Instance Subnetの構築](../step02-runner-subnet/README.md)が完了していること
- **重要**: ACRにRunnerイメージ(`github-runner:latest`)がプッシュ済みであること
  - Step 01の[BUILD_GUIDE.md](../step01-container-registry/BUILD_GUIDE.md)を参照してイメージをビルド・プッシュしてください

> **⚠️ 注意**: ACRが完全閉域構成のため、ローカル環境から直接ACRの内容を確認することはできません。これは正常な動作です。イメージが存在するかの確認が必要な場合は、後述のトラブルシューティングセクションを参照してください。

確認方法:
```powershell
# ACRの確認
$ACR_NAME = "acrinternalragdev"
$RESOURCE_GROUP = "rg-internal-rag-dev"
az acr show --name $ACR_NAME --query "{Name:name, LoginServer:loginServer, PublicAccess:publicNetworkAccess}"

# Subnetの確認
$ENV_NAME = "dev"
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances
```

## デプロイ手順

### 1. パラメータファイルの編集

`parameters.bicepparam` を開いて、環境に合わせて値を設定します:

```bicep
using './main.bicep'

param location = 'japaneast'
param environmentName = 'dev'
param vnetName = 'vnet-internal-rag-dev'
param containerSubnetName = 'snet-container-instances'
param acrName = 'acrinternalragdev'  // Step 01で作成したACR名
param containerInstanceName = 'aci-github-runner-dev'
param runnerImageTag = 'latest'
param cpuCores = 2
param memoryInGb = 4
```

### 2. Container Instanceのデプロイ

```powershell
# Step 03ディレクトリに移動
cd bicep/step03-container-instance

# 1. 一時的にパブリックアクセス有効化
az acr update --name $ACR_NAME --public-network-enabled true --default-action Allow

# 2. デプロイ実行
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# 3. パブリックアクセス無効化
az acr update --name acrinternalragdev --default-action Deny --public-network-enabled false
```

**所要時間**: 約3-5分

### 3. デプロイ結果の確認

```powershell
# Container Instance名を取得
$ACI_NAME = az deployment group show `
  --resource-group $RESOURCE_GROUP `
  --name main `
  --query properties.outputs.containerInstanceName.value `
  --output tsv

echo "Container Instance Name: $ACI_NAME"

# Container Instanceの詳細を確認
az container show `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --query "{Name:name, State:instanceView.state, IP:ipAddress.ip, Subnet:subnetIds[0].id}"
```

**期待される出力**:
```json
{
  "Name": "aci-github-runner-dev",
  "State": "Failed",
  "IP": null,
  "Subnet": "/subscriptions/.../subnets/snet-container-instances"
}
```

> **⚠️ 重要**: `State: "Failed"`は**正常な状態**です。これはContainer Instanceが作成され、イメージのプルに成功したものの、GitHub Runner起動に必要な環境変数（`RUNNER_TOKEN`, `RUNNER_REPOSITORY_URL`）が設定されていないため、コンテナが終了したことを示しています。これらの環境変数は、GitHub Actionsワークフロー実行時に動的に設定されます。

**実際のプロビジョニング状態を確認**:
```powershell
az container show `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --query "{Name:name, ProvisioningState:provisioningState, RestartPolicy:restartPolicy, ManagedIdentity:identity.type}"
```

**期待される出力**:
```json
{
  "Name": "aci-github-runner-dev",
  "ProvisioningState": "Succeeded",
  "RestartPolicy": "Never",
  "ManagedIdentity": "SystemAssigned"
}
```

## 詳細解説

### Container Instanceの設定

#### Managed Identityの使用

```bicep
identity: {
  type: 'SystemAssigned'
}
```

**メリット**:
- ✅ シークレット管理不要
- ✅ 自動的にAzure ADで管理
- ✅ ACRへの認証に使用

#### ACR認証(Managed Identity)

```bicep
imageRegistryCredentials: []  // 空配列 = Managed Identityを使用
```

**動作**:
1. Container InstanceにSystemAssigned Managed Identityが付与される
2. そのManaged IdentityにACR Pullロールが割り当てられる
3. ACIがACRからイメージをプルする際、Managed Identityで自動認証される

**従来のAdmin User方式との比較**:

| 方式 | セキュリティ | 管理容易性 | 推奨度 |
|------|-------------|-----------|--------|
| **Managed Identity** | ✅ 高 | ✅ 容易 | ⭐⭐⭐ 推奨 |
| Admin User | ⚠️ 中 | △ パスワード管理必要 | ❌ 非推奨 |

#### vNet統合

```bicep
subnetIds: [
  {
    id: containerSubnet.id
  }
]
```

**効果**:
- Container InstanceがvNet内に配置される
- Private Endpoint経由でACRにアクセス可能
- 閉域環境を維持

#### 再起動ポリシー

```bicep
restartPolicy: 'Never'
```

**理由**:
- Self-hosted Runnerは1つのジョブを実行したら終了する(Ephemeral)
- 自動再起動は不要
- GitHub Actionsワークフローで明示的に起動・停止を制御

### ACRへのアクセス権限

#### Role Assignment

```bicep
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerInstance.id, acr.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerInstance.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
```

**ポイント**:
- `AcrPull`ロール: イメージのプルのみ許可(プッシュは不可)
- `principalId`: Container InstanceのManaged IdentityのID
- `scope`: ACR全体に対する権限

## GitHub Actionsでの使用方法

### ワークフローでの起動・停止

事前に作成されたACIをGitHub Actionsワークフローで起動・停止します。

**ワークフローの例** (sample_repoの`.github/workflows/deploy-functions.yml`参照):

```yaml
jobs:
  setup-runner:
    runs-on: ubuntu-latest
    steps:
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Start Container Instance
        run: |
          # Container Instanceを起動
          az container start \
            --resource-group $RESOURCE_GROUP \
            --name $CONTAINER_GROUP_NAME
          
          # 起動完了を待機
          echo "Waiting for container to start..."
          sleep 30

  build-and-deploy:
    needs: setup-runner
    runs-on: self-hosted
    steps:
      - name: Deploy Application
        run: |
          # デプロイ処理
          echo "Deploying..."

  cleanup:
    needs: build-and-deploy
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Stop Container Instance
        run: |
          # Container Instanceを停止
          az container stop \
            --resource-group $RESOURCE_GROUP \
            --name $CONTAINER_GROUP_NAME
```

### ACIの状態管理

**起動前**:
```powershell
az container show --name $ACI_NAME --query "instanceView.state"
# 出力: "Stopped"
```

**起動後**:
```powershell
az container show --name $ACI_NAME --query "instanceView.state"
# 出力: "Running"
```

## 検証

### 1. Container Instance作成確認

```powershell
az container show `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --query "{Name:name, State:instanceView.state, RestartPolicy:restartPolicy, Subnet:subnetIds[0].id}"
```

**期待される出力**:
```json
{
  "Name": "aci-github-runner-dev",
  "State": "Succeeded",
  "RestartPolicy": "Never",
  "Subnet": "/subscriptions/.../subnets/snet-container-instances"
}
```

### 2. Managed Identity確認

```powershell
az container show `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --query "identity.{Type:type, PrincipalId:principalId}"
```

**期待される出力**:
```json
{
  "Type": "SystemAssigned",
  "PrincipalId": "<guid>"
}
```

### 3. ACR Pull権限確認

```powershell
# Managed IdentityのPrincipal IDを取得
$PRINCIPAL_ID = az container show `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --query "identity.principalId" `
  --output tsv

# ACRへのロール割り当てを確認
az role assignment list `
  --assignee $PRINCIPAL_ID `
  --scope $(az acr show --name $ACR_NAME --query id --output tsv) `
  --query "[].{Role:roleDefinitionName, Scope:scope}" `
  --output table
```

**期待される出力**:
```
Role     Scope
-------  --------------------------------------------------
AcrPull  /subscriptions/.../registries/acrinternalragdev
```

### 4. ACIからACRへのイメージプル確認

```powershell
# Container Instanceのログを確認(起動時のイメージプルログ)
az container logs `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --container-name github-runner
```

## トラブルシューティング

### エラー: Container Instance作成に失敗

**エラーメッセージ**: `The image 'acrinternalragdev.azurecr.io/github-runner:latest' could not be pulled`

**原因**:
1. ACRにイメージが存在しない
2. Managed IdentityにACR Pull権限が付与されていない
3. ACRのPrivate Endpointが正しく構成されていない

**対処法**:

```powershell
# 1. ACRにイメージが存在するか確認(閉域状態では確認不可)
# 一時的にパブリックアクセスを有効化して確認
az acr update --name $ACR_NAME --public-network-enabled true --default-action Allow

# イメージの存在確認
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table

# イメージが存在しない場合は、Step 01のBUILD_GUIDEを参照してビルド・プッシュ
# cd ../step01-container-registry
# az acr build --registry $ACR_NAME --image github-runner:latest --file Dockerfile .

# 確認後、再度閉域化
az acr update --name $ACR_NAME --default-action Deny --public-network-enabled false

# 2. Managed Identityの権限を確認
$PRINCIPAL_ID = az container show --resource-group $RESOURCE_GROUP --name $ACI_NAME --query "identity.principalId" -o tsv
az role assignment list --assignee $PRINCIPAL_ID --output table

# 3. 権限が付与されていない場合、手動で付与
az role assignment create `
  --assignee $PRINCIPAL_ID `
  --role AcrPull `
  --scope $(az acr show --name $ACR_NAME --query id -o tsv)
```

### エラー: Subnetが見つからない

**エラーメッセージ**: `The subnet 'snet-container-instances' was not found`

**対処法**:

```powershell
# Subnetの存在確認
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances

# Subnetが存在しない場合、Step 02を実行
cd bicep/step02-runner-subnet
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
```

### Container Instanceが起動しない

**症状**: Container Instanceが`Succeeded`状態にならない

**確認事項**:

```powershell
# Container Instanceの詳細状態を確認
az container show `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --query "{State:instanceView.state, Events:instanceView.events}" `
  --output json

# ログを確認
az container logs `
  --resource-group $RESOURCE_GROUP `
  --name $ACI_NAME `
  --container-name github-runner
```

**よくある原因**:
- イメージが正しくプルされていない
- 環境変数が不足している(RUNNER_TOKEN, RUNNER_REPOSITORY_URLなど)
- vNet設定が正しくない

### エラー: Private Endpoint経由でACRにアクセスできない

**症状**: Container Instanceの初回デプロイ時に`InaccessibleImage`エラーが発生する

**原因**: 
Container InstanceがvNet内に配置されていても、初回のイメージプル時にPrivate Endpoint経由でACRにアクセスできない場合があります。これは以下の理由による可能性があります:
- DNS解決の遅延
- ネットワーク接続の初期化タイミング
- Admin User認証情報を使用していても、ネットワーク的にACRに到達できない

**対処法**:

Container Instanceの初回デプロイ時のみ、ACRを一時的にパブリックアクセス可能にします:

```powershell
# 1. Admin Userを有効化（Bicepテンプレートで認証情報を使用するため）
az acr update --name $ACR_NAME --admin-enabled true

# 2. ACRを一時的にパブリック化
az acr update --name $ACR_NAME --public-network-enabled true --default-action Allow

# 3. Container Instanceをデプロイ
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# 4. デプロイ成功後、ACRを再度完全閉域化
az acr update --name $ACR_NAME --default-action Deny --public-network-enabled false

# 5. Admin Userも無効化（オプション、推奨）
az acr update --name $ACR_NAME --admin-enabled false
```

> **💡 ヒント**: 一度Container Instanceが作成されれば、次回以降の起動時（`az container start`）はPrivate Endpoint経由で問題なくアクセスできます。この手順は初回デプロイ時のみ必要です。

> **⚠️ 重要**: Container Instanceを削除して再作成する場合は、上記の手順1から再度実行してください。Admin Userを無効化している場合は、必ず有効化してからデプロイしてください。

> **⚠️ セキュリティ注意**: パブリックアクセスは必ずデプロイ完了後に無効化してください。

## ベストプラクティス

### セキュリティ

- ✅ **Managed Identity使用**: Admin Userは避ける
- ✅ **Private Endpoint経由**: ACRへの閉域アクセス
- ✅ **最小権限の原則**: AcrPullロールのみ付与
- ✅ **vNet統合**: Container InstanceをvNet内に配置

### コスト最適化

- ✅ **停止時は課金なし**: Container Instanceは停止中は課金されません
- ✅ **適切なリソース設定**: CPU 2コア、メモリ 4GBで十分
- ✅ **Never restart policy**: 不要な再起動を避ける

### 運用管理

- ✅ **タグ付け**: 環境、プロジェクト、目的を明記
- ✅ **命名規則**: `aci-github-runner-<環境名>`
- ✅ **ログ監視**: Application Insightsと連携

## イメージ更新フロー

Runnerイメージを更新する場合の手順:

```powershell
# 1. ACRを一時的にパブリック化
az acr update --name $ACR_NAME --public-network-enabled true --default-action Allow

# 2. 新しいイメージをビルド・プッシュ
az acr build `
  --registry $ACR_NAME `
  --image github-runner:latest `
  --image github-runner:1.1.0 `
  --file Dockerfile `
  .

# 3. ACRを再度閉域化
az acr update --name $ACR_NAME --public-network-enabled false --default-action Deny

# 4. Container Instanceを再作成(新しいイメージを使用)
az container delete --resource-group $RESOURCE_GROUP --name $ACI_NAME --yes

az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
```

## 次のステップ

Container Instanceの作成が完了したら、次のステップに進みましょう:

- [Step 04: Key Vaultの構築](../step04-keyvault/README.md) - シークレット管理
- [Step 05: GitHub Actionsの設定](../step05-github-actions/README.md) - ACIの起動・停止
- [デプロイガイドに戻る](../../docs/deployment-guide.md)

## 参考リンク

- [Azure Container Instances ドキュメント](https://learn.microsoft.com/ja-jp/azure/container-instances/)
- [Managed Identityを使用したACR認証](https://learn.microsoft.com/ja-jp/azure/container-registry/container-registry-authentication-managed-identity)
- [GitHub Actions Self-hosted Runners](https://docs.github.com/ja/actions/hosting-your-own-runners)
- [Container InstancesのvNet統合](https://learn.microsoft.com/ja-jp/azure/container-instances/container-instances-vnet)
