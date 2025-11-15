using './main.bicep'

// ============================================================================
// Container Instance Subnetのパラメータファイル
// ============================================================================

// デプロイ先のリージョン
param location = 'japaneast'

// 環境名
param environmentName = 'dev'

// 既存のVirtual Network名
// internal_rag_step_by_stepで作成した名前を指定
param vnetName = 'vnet-internal-rag-dev'

// Container Instance Subnetのアドレスプレフィックス
// 既存のSubnetと重複しないように設定
// Note: 10.0.5.0/28 はDNS Private Resolver用に使用されています
param containerSubnetPrefix = '10.0.6.0/24'

// タグ
param tags = {
  Environment: 'Development'
  Project: 'Internal RAG Deployment'
  ManagedBy: 'Bicep'
  CostCenter: 'IT'
}
