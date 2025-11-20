// ============================================================================
// 統合版: GitHub Actions デプロイ環境の一括構築
// ============================================================================
// このBicepファイルは、GitHub Actionsを使用した閉域Web Appsへの
// アプリケーションデプロイに必要なすべてのリソースを一度にデプロイします
// - Step 01: Azure Container Registry (ACR)
// - Step 02: Container Instance Subnet (Self-hosted Runner用)
// - Step 03: Key Vault with Private Endpoint
// - Network Security Group

targetScope = 'resourceGroup'

// ============================================================================
// パラメータ
// ============================================================================

@description('デプロイ先のリージョン')
param location string = resourceGroup().location

@description('環境名 (例: dev, stg, prod)')
@minLength(3)
@maxLength(10)
param environmentName string

@description('Virtual Network名 (既存のVNetを指定)')
param vnetName string

@description('Container Instance Subnetのアドレスプレフィックス')
param containerSubnetPrefix string = '10.0.6.0/24'

@description('Key Vault名')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'kv-gh-runner-${environmentName}'

@description('現在のユーザーのオブジェクトID（初期管理者用）')
param adminObjectId string

@description('ACR名（グローバルで一意、小文字英数字のみ、5-50文字）')
@minLength(5)
@maxLength(50)
param acrName string

@description('ACRのSKU（Private LinkにはPremium必須）')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

@description('Private Endpoint を配置する既存のサブネット名')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('ACRの管理者ユーザーを有効化（非推奨、Managed Identity推奨）')
param enableAdminUser bool = false

@description('パブリックネットワークアクセスの制御')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('タグ')
param tags object = {
  Environment: environmentName
  Project: 'GitHub Actions Deployment'
  ManagedBy: 'Bicep'
}

// ============================================================================
// Step 01: Azure Container Registry (ACR)
// ============================================================================

module acr '../step01-container-registry/main.bicep' = {
  name: 'deploy-acr'
  params: {
    location: location
    environmentName: environmentName
    acrName: acrName
    vnetName: vnetName
    privateEndpointSubnetName: privateEndpointSubnetName
    acrSku: acrSku
    enableAdminUser: enableAdminUser
    publicNetworkAccess: publicNetworkAccess
  }
}

// ============================================================================
// Step 02: Container Instance Subnet
// ============================================================================

module runnerSubnet '../step02-runner-subnet/main.bicep' = {
  name: 'deploy-runner-subnet'
  params: {
    location: location
    environmentName: environmentName
    vnetName: vnetName
    containerSubnetPrefix: containerSubnetPrefix
    tags: tags
  }
  dependsOn: [
    acr
  ]
}

// ============================================================================
// Step 03: Key Vault
// ============================================================================

module keyVault '../step03-keyvault/main.bicep' = {
  name: 'deploy-keyvault'
  params: {
    location: location
    environmentName: environmentName
    vnetName: vnetName
    keyVaultName: keyVaultName
    adminObjectId: adminObjectId
    tags: tags
  }
  dependsOn: [
    runnerSubnet
  ]
}

// ============================================================================
// 出力
// ============================================================================

@description('ACRのリソースID')
output acrId string = acr.outputs.acrId

@description('ACR名')
output acrName string = acr.outputs.acrName

@description('ACRのLogin Server')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('Container Instance SubnetのリソースID')
output containerSubnetId string = runnerSubnet.outputs.containerSubnetId

@description('Container Instance Subnet名')
output containerSubnetName string = runnerSubnet.outputs.containerSubnetName

@description('NSGのリソースID')
output nsgId string = runnerSubnet.outputs.nsgId

@description('Key VaultのリソースID')
output keyVaultId string = keyVault.outputs.keyVaultId

@description('Key Vault名')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Private EndpointのリソースID')
output keyVaultPrivateEndpointId string = keyVault.outputs.privateEndpointId

@description('デプロイ完了メッセージ')
output deploymentMessage string = 'GitHub Actions デプロイ環境のセットアップが完了しました。次はGitHub Actionsワークフローを設定してください。'
