// ============================================================================
// Step 02: Key Vaultの構築
// ============================================================================
// このBicepファイルは、デプロイ用認証情報を管理するKey Vaultを構築します
// - Key Vault
// - Private Endpoint
// - アクセスポリシー設定

targetScope = 'resourceGroup'

// ============================================================================
// パラメータ
// ============================================================================

@description('デプロイ先のリージョン')
param location string = resourceGroup().location

@description('環境名')
@minLength(3)
@maxLength(10)
param environmentName string

@description('既存のVirtual Network名')
param vnetName string

@description('Key Vault名 (グローバルで一意、3-24文字)')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'kv-deploy-${environmentName}'

@description('現在のユーザーのオブジェクトID（初期管理者用）')
param adminObjectId string

@description('タグ')
param tags object = {
  Environment: environmentName
  Project: 'Internal RAG Deployment'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 変数
// ============================================================================

var privateEndpointName = 'pe-keyvault-${environmentName}'
var privateDnsZoneName = 'privatelink.vaultcore.azure.net'

// ============================================================================
// 既存リソースの参照
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-private-endpoints'
}

// ============================================================================
// Private DNS Zone
// ============================================================================

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// ============================================================================
// Key Vault
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: false // アクセスポリシーを使用
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: adminObjectId
        permissions: {
          keys: [
            'get'
            'list'
            'create'
            'update'
            'delete'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
          ]
          certificates: [
            'get'
            'list'
            'create'
            'update'
            'delete'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Private Endpoint
// ============================================================================

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// 出力
// ============================================================================

@description('Key VaultのリソースID')
output keyVaultId string = keyVault.id

@description('Key Vault名')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Private EndpointのリソースID')
output privateEndpointId string = privateEndpoint.id
