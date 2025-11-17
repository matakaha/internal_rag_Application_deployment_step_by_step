// ============================================================================
// Step 01: Container Instance Subnet の構築
// ============================================================================
// このBicepファイルは、Self-hosted GitHub Actions Runner用のSubnetを
// 既存のVNetに追加します
// - Container Instance用Subnet
// - NSG設定

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

@description('既存のVirtual Network名')
param vnetName string

@description('Container Instance Subnetのアドレスプレフィックス')
param containerSubnetPrefix string = '10.0.6.0/24'

@description('タグ')
param tags object = {
  Environment: environmentName
  Project: 'Internal RAG Deployment'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 変数
// ============================================================================

var nsgContainerName = 'nsg-container-instances-${environmentName}'
var containerSubnetName = 'snet-container-instances'

// ============================================================================
// 既存リソースの参照
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// ============================================================================
// Network Security Group
// ============================================================================

resource nsgContainer 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgContainerName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          description: 'VNet内からの通信を許可'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowHttpsOutbound'
        properties: {
          description: 'HTTPS通信を許可（GitHub, Azure API等）'
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowVnetOutbound'
        properties: {
          description: 'VNet内への通信を許可'
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ============================================================================
// Container Instance Subnet
// ============================================================================

// 既存のSubnetリストを取得して、最後のSubnetに依存させる
resource existingSubnets 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-compute'
}

resource containerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: containerSubnetName
  dependsOn: [
    existingSubnets // 既存Subnetの後に作成
  ]
  properties: {
    addressPrefix: containerSubnetPrefix
    delegations: [
      {
        name: 'delegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsgContainer.id
    }
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          location
        ]
      }
    ]
  }
}

// ============================================================================
// 出力
// ============================================================================

@description('Container Instance SubnetのリソースID')
output containerSubnetId string = containerSubnet.id

@description('Container Instance Subnet名')
output containerSubnetName string = containerSubnet.name

@description('NSGのリソースID')
output nsgId string = nsgContainer.id
