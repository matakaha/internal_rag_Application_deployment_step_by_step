# Step 01: Container Instance Subnetの構築

このステップでは、Self-hosted GitHub Actions Runner用のSubnetを既存のVNetに追加します。

## 学習目標

このステップを完了すると、以下を理解できます:

- 既存VNetへのSubnet追加方法
- Container Instance用のSubnet委任設定
- NSGによるContainer Instance通信制御
- Service Endpointの設定

## 作成されるリソース

| リソース | 種類 | 目的 |
|---------|------|------|
| Container Instance Subnet | サブネット | Self-hosted Runner実行環境 |
| NSG | `Microsoft.Network/networkSecurityGroups` | 通信制御 |

## 前提条件

- [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step) Step 01が完了していること
- Virtual Network `vnet-internal-rag-<環境名>` が存在すること

確認方法:
```powershell
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ENV_NAME = "dev"

az network vnet show `
  --resource-group $RESOURCE_GROUP `
  --name "vnet-internal-rag-$ENV_NAME"
```

## デプロイ手順

### 1. パラメータファイルの編集

`parameters.bicepparam` を開いて、環境に合わせて値を設定します:

```bicep
using './main.bicep'

param location = 'japaneast'
param environmentName = 'dev'
param vnetName = 'vnet-internal-rag-dev'
param containerSubnetPrefix = '10.0.6.0/24'
```

**重要**: `containerSubnetPrefix` が既存Subnetと重複しないことを確認してください。

> **Note**: 10.0.5.0/28 は DNS Private Resolver 用に使用されているため、10.0.6.0/24 を使用します。

### 2. 既存Subnetの確認

```powershell
# 既存のSubnetを確認
az network vnet subnet list `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --query "[].{Name:name, AddressPrefix:addressPrefix}" `
  --output table
```

**期待される出力**:
```
Name                    AddressPrefix
----------------------  ---------------
snet-private-endpoints  10.0.1.0/24
snet-app-integration    10.0.2.0/24
snet-compute            10.0.3.0/24
snet-dns-resolver       10.0.5.0/28
```

10.0.6.0/24が使用されていないことを確認してください（10.0.5.0/28はDNS Private Resolver用）。

### 3. デプロイの実行

```powershell
# Step 01ディレクトリに移動
cd bicep/step01-runner-subnet

# デプロイ実行
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
```

**所要時間**: 約2-3分

### 4. デプロイ結果の確認

```powershell
# Subnet確認
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances `
  --query "{Name:name, AddressPrefix:addressPrefix, Delegations:delegations[].serviceName}"

# NSG確認
az network nsg show `
  --resource-group $RESOURCE_GROUP `
  --name "nsg-container-instances-$ENV_NAME" `
  --query "{Name:name, SecurityRules:length(securityRules)}"
```

## 詳細解説

### Container Instance Subnet

#### Subnet委任

```bicep
delegations: [
  {
    name: 'delegation'
    properties: {
      serviceName: 'Microsoft.ContainerInstance/containerGroups'
    }
  }
]
```

**ポイント**:
- Container Instancesを使用するには委任が必須
- `Microsoft.ContainerInstance/containerGroups` への委任を設定

#### Service Endpoint

```bicep
serviceEndpoints: [
  {
    service: 'Microsoft.KeyVault'
    locations: [location]
  }
]
```

**ポイント**:
- Key VaultへのアクセスをService Endpoint経由で行う
- Private Endpointの代替として使用可能
- コスト削減に有効

> **Note (ACR利用時)**: Azure Container Registry (ACR) からのイメージプルは、ACRのPrivate Endpoint経由で行われます。Container Instance SubnetからACRへの直接的なService Endpointは不要です。ACRはPrivate Endpoint Subnet (`snet-private-endpoints`) に配置されたPrivate Endpointを経由してアクセスされます（Step 00.5参照）。

### Network Security Group

#### インバウンドルール

```bicep
{
  name: 'AllowVnetInbound'
  properties: {
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefix: 'VirtualNetwork'
  }
}
```

**ポイント**:
- VNet内部からの通信のみ許可
- 外部からの直接アクセスは拒否

#### アウトバウンドルール

```bicep
{
  name: 'AllowHttpsOutbound'
  properties: {
    priority: 100
    direction: 'Outbound'
    access: 'Allow'
    protocol: 'Tcp'
    destinationAddressPrefix: 'Internet'
    destinationPortRange: '443'
  }
}
```

**ポイント**:
- GitHubへのアクセスに必要（Runner登録、コード取得）
- Azure API（Container Registry、Web Apps等）へのアクセス
- HTTPS (443)のみ許可でセキュリティ確保

> **Note (ACR利用時の注意)**: 
> - ACR Private Endpoint経由のイメージプルは、vNet内部通信として扱われます
> - GitHubへのRunner登録とジョブ通信には引き続きHTTPS (443)のアウトバウンド許可が必要です
> - ACRからのイメージプルにはインターネットアクセスは不要です（完全閉域）

## 検証

### 1. Subnet作成確認

```powershell
az network vnet subnet show `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --name snet-container-instances
```

**確認項目**:
- `addressPrefix`: 10.0.6.0/24
- `delegations[0].serviceName`: Microsoft.ContainerInstance/containerGroups
- `serviceEndpoints[0].service`: Microsoft.KeyVault

### 2. NSGルール確認

```powershell
az network nsg rule list `
  --resource-group $RESOURCE_GROUP `
  --nsg-name "nsg-container-instances-$ENV_NAME" `
  --output table
```

**期待されるルール**:
- AllowVnetInbound (Inbound, Priority 100)
- AllowHttpsOutbound (Outbound, Priority 100)
- AllowVnetOutbound (Outbound, Priority 110)

### 3. VNetリソースの全体確認

```powershell
az network vnet subnet list `
  --resource-group $RESOURCE_GROUP `
  --vnet-name "vnet-internal-rag-$ENV_NAME" `
  --output table
```

**期待される出力**:
```
Name                      AddressPrefix    PrivateEndpointNetworkPolicies    Delegations
------------------------  ---------------  --------------------------------  -------------------------
snet-private-endpoints    10.0.1.0/24      Disabled                          -
snet-app-integration      10.0.2.0/24      Enabled                           Microsoft.Web/serverFarms
snet-compute              10.0.3.0/24      Enabled                           -
snet-dns-resolver         10.0.5.0/28      Enabled                           Microsoft.Network/dnsResolvers
snet-container-instances  10.0.6.0/24      Enabled                           Microsoft.ContainerInstance/containerGroups
```

## トラブルシューティング

### エラー: Subnetのアドレス空間が重複

**原因**: 指定したアドレスプレフィックスが既存Subnetと重複

**対処法**:
1. 既存Subnetのアドレス範囲を確認
2. `parameters.bicepparam` の `containerSubnetPrefix` を変更
3. 例: `10.0.7.0/24` に変更（10.0.5.0/28はDNS Resolver、10.0.6.0/24はContainer Instance用）

### エラー: Subnet委任に失敗

**原因**: Subnetに既に別のリソースが配置されている

**対処法**:
1. 新しいSubnetを作成
2. 既存リソースがないことを確認

### エラー: NSGの割り当てに失敗

**原因**: NSGリソースの作成前にSubnetに割り当てようとした

**対処法**:
- Bicepの依存関係が正しく設定されているか確認
- 通常は自動的に解決されるため、再デプロイを試行

## ベストプラクティス

### Subnet設計
- ✅ Container Instances専用Subnetを用意
- ✅ 将来の拡張を考慮してアドレス範囲を確保
- ✅ Subnet委任を正しく設定

### NSG設定
- ✅ 必要最小限の通信のみ許可
- ✅ アウトバウンドはHTTPS (443)のみ
- ✅ ログを有効化して通信を監視

### Service Endpoint
- ✅ Key Vault用Service Endpointを設定
- ✅ Private Endpointより低コスト
- ✅ セキュリティは十分確保

## 次のステップ

Container Instance用Subnetが完成したら、次のステップに進みましょう:

- [Step 00.5: Azure Container Registryの構築](../step00.5-container-registry/README.md) - Runnerイメージの事前ビルド（推奨）
- [Step 02: Key Vaultの構築](../step02-keyvault/README.md)
- [デプロイガイドに戻る](../../docs/deployment-guide.md)

> **推奨**: 閉域環境でのセキュリティと安定性を確保するため、先にStep 00.5でACRとRunnerイメージを準備することを強く推奨します。

## 参考リンク

- [Azure Container Instances](https://learn.microsoft.com/ja-jp/azure/container-instances/)
- [Virtual Network サービス エンドポイント](https://learn.microsoft.com/ja-jp/azure/virtual-network/virtual-network-service-endpoints-overview)
- [サブネットの委任](https://learn.microsoft.com/ja-jp/azure/virtual-network/subnet-delegation-overview)
