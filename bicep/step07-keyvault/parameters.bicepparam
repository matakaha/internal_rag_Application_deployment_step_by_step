using './main.bicep'

// ============================================================================
// Key Vaultのパラメータファイル
// ============================================================================

// デプロイ先のリージョン
param location = 'japaneast'

// 環境名
param environmentName = 'dev'

// 既存のVirtual Network名
param vnetName = 'vnet-internal-rag-dev'

// Key Vault名 (グローバルで一意、3-24文字、英数字とハイフンのみ)
param keyVaultName = 'kv-deploy-dev'

// 現在のユーザーのオブジェクトID
// 以下のコマンドで取得: az ad signed-in-user show --query id --output tsv
param adminObjectId = '<YOUR_OBJECT_ID>'

// タグ
param tags = {
  Environment: 'Development'
  Project: 'Internal RAG Deployment'
  ManagedBy: 'Bicep'
  CostCenter: 'IT'
}
