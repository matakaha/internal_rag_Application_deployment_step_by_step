# Step 03: GitHub Actions Self-hosted Runner (Container Instance)の構築

このステップでは、GitHub Actions Self-hosted Runner用のAzure Container Instanceを**事前に作成**します。

## 学習目標

このステップを完了すると、以下を理解できます:

- Azure Container Instanceの作成とvNet統合
- ACRからのイメージプル(Private Endpoint経由)
- Managed Identityを使用したACR認証
- GitHub Actions Self-hosted Runnerの事前準備

## なぜ事前にACIを作成するのか?

### 課題: GitHub ActionsからACRへの接続問題

従来の方法では、GitHub Actionsワークフローの中でACIを作成し、その際にACRからRunnerイメージをプルしていました。しかし、この方法には以下の問題がありました:

1. **ACRをパブリックに公開する必要がある**: GitHub Actions(ubuntu-latest runner)はインターネット上で動作するため、ACRにアクセスするにはパブリックアクセスを有効にする必要がありました
2. **セキュリティリスク**: ACRのパブリック公開は、セキュリティポリシーに反する可能性があります
3. **設定の煩雑さ**: デプロイのたびにACRのパブリックアクセスを有効化・無効化する必要がありました

### 解決策: 事前作成アプローチ

ACIを**事前に作成**しておくことで、以下のメリットが得られます:

✅ **ACRを完全閉域に保てる**: ACIとACRは同じvNet内にあるため、Private Endpoint経由でイメージをプルできます  
✅ **GitHub Actionsの役割を最小化**: ワークフローではACIの起動・停止のみを行い、ACRへの接続は不要になります  
✅ **シンプルな運用**: イメージ更新時のみACRを一時的にパブリック化すればよく、通常運用では完全閉域を維持できます

### アーキテクチャの変更

**従来の方法**:
```
GitHub Actions (ubuntu-latest)
  ↓ ACIを作成
  ↓ ACRからイメージをプル (パブリックアクセス必要!)
Azure Container Instance
  ↓ Self-hosted Runnerとして動作
```

**新しい方法**:
```
[事前準備フェーズ]
Azure Container Instance (事前作成済み)
  ← ACRからイメージをプル (Private Endpoint経由、閉域!)

[実行フェーズ]
GitHub Actions (ubuntu-latest)
  ↓ ACIを起動 (az container start)
  ↓ ACRへの接続は不要!
Azure Container Instance
  ↓ Self-hosted Runnerとして動作
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
- ACRにRunnerイメージ(`github-runner:latest`)がプッシュ済みであること

確認方法:
```powershell
# ACRの確認
$ACR_NAME = "acrinternalragdev"
az acr show --name $ACR_NAME --query "{Name:name, LoginServer:loginServer}"

# Runnerイメージの確認(パブリックアクセスが一時的に有効な場合のみ)
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table

# Subnetの確認
$RESOURCE_GROUP = "rg-internal-rag-dev"
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

# デプロイ実行
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
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
  "State": "Succeeded",
  "IP": null,  // vNet統合時はプライベートIPのみ
  "Subnet": "/subscriptions/.../subnets/snet-container-instances"
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
# 1. ACRにイメージが存在するか確認(パブリックアクセス有効時のみ)
az acr update --name $ACR_NAME --public-network-enabled true
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table
az acr update --name $ACR_NAME --public-network-enabled false

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
