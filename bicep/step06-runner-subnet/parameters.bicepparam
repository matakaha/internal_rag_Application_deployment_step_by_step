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

// Container Instance SubnetのアドレスプレフィックS
// 既存のSubnetと重複しないように設定
param containerSubnetPrefix = '10.0.5.0/24'

// タグ
param tags = {
  Environment: 'Development'
  Project: 'Internal RAG Deployment'
  ManagedBy: 'Bicep'
  CostCenter: 'IT'
}
