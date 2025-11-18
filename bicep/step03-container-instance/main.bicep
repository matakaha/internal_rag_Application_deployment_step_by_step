// ============================================================================
// Step 03: GitHub Actions Self-hosted Runner (Container Instance)の構築
// ============================================================================
// このBicepファイルは、事前に作成しておくGitHub Actions Self-hosted Runner用の
// Azure Container Instanceを構築します

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

@description('既存のContainer Instance Subnet名')
param containerSubnetName string = 'snet-container-instances'

@description('既存のAzure Container Registry名')
param acrName string

@description('Container Instanceの名前')
param containerInstanceName string = 'aci-github-runner-${environmentName}'

@description('GitHub Runnerイメージのタグ')
param runnerImageTag string = 'latest'

@description('CPU数')
param cpuCores int = 2

@description('メモリ(GB)')
param memoryInGb int = 4

@description('タグ')
param tags object = {
  Environment: environmentName
  Project: 'Internal RAG Deployment'
  ManagedBy: 'Bicep'
  Purpose: 'GitHub Actions Runner'
}

// ============================================================================
// 変数
// ============================================================================

var runnerImageName = '${acrName}.azurecr.io/github-runner:${runnerImageTag}'

// ============================================================================
// 既存リソースの参照
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource containerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: containerSubnetName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// ============================================================================
// Container Instance
// ============================================================================

resource containerInstance 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerInstanceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: 'Standard'
    containers: [
      {
        name: 'github-runner'
        properties: {
          image: runnerImageName
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
          environmentVariables: [
            {
              name: 'RUNNER_NAME'
              value: 'standby-runner-${environmentName}'
            }
            {
              name: 'RUNNER_LABELS'
              value: 'self-hosted,azure,vnet'
            }
            // 注: RUNNER_TOKEN と RUNNER_REPOSITORY_URL は
            // GitHub Actions ワークフロー内で Container Instance を再起動する際に
            // 動的に設定されます
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Never'
    subnetIds: [
      {
        id: containerSubnet.id
      }
    ]
    imageRegistryCredentials: [
      {
        server: acr.properties.loginServer
        username: acr.listCredentials().username
        password: acr.listCredentials().passwords[0].value
      }
    ]
  }
}

// ============================================================================
// ACRへのアクセス権限付与(Managed Identityを使用)
// ============================================================================

// ACR Pull権限をContainer InstanceのManaged Identityに付与
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerInstance.id, acr.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerInstance.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// 出力
// ============================================================================

@description('Container InstanceのリソースID')
output containerInstanceId string = containerInstance.id

@description('Container Instance名')
output containerInstanceName string = containerInstance.name

@description('Managed IdentityのPrincipal ID')
output managedIdentityPrincipalId string = containerInstance.identity.principalId
