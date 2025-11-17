@description('Azure リージョン')
param location string = resourceGroup().location

@description('環境名 (dev, stg, prod)')
param environmentName string

@description('Azure Container Registry名（グローバルで一意、小文字英数字のみ、5-50文字）')
@minLength(5)
@maxLength(50)
param acrName string

@description('既存のVirtual Network名')
param vnetName string

@description('Private Endpoint を配置する既存のサブネット名')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('ACRのSKU（Private LinkにはPremium必須）')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

@description('ACRの管理者ユーザーを有効化（非推奨、Managed Identity推奨）')
param enableAdminUser bool = false

@description('パブリックネットワークアクセスの制御')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

// 既存のVirtual Networkを参照
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName
}

// 既存のPrivate Endpoint Subnetを参照
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: enableAdminUser
    publicNetworkAccess: publicNetworkAccess
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled' // コスト削減のため無効化（本番環境では検討）
  }
  tags: {
    Environment: environmentName
    Purpose: 'GitHub Actions Runner Container Registry'
  }
}

// Private DNS Zone for ACR
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: {
    Environment: environmentName
  }
}

// Private DNS Zone と VNet のリンク
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// ACR用のPrivate Endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-acr-${environmentName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'acr-connection'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
  tags: {
    Environment: environmentName
  }
}

// Private Endpoint の DNS 設定
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
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

// 出力
output acrId string = acr.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output privateEndpointId string = privateEndpoint.id
output privateDnsZoneId string = privateDnsZone.id
