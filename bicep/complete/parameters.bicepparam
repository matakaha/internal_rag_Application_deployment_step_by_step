using './main.bicep'

// ============================================================================
// GitHub Actions デプロイ環境のパラメータファイル（統合版）
// ============================================================================
// このファイルの値を環境に合わせて編集してください

// デプロイ先のリージョン
param location = 'japaneast'

// 環境名 (dev, stg, prodなど)
// リソース名のサフィックスとして使用されます
param environmentName = 'dev'

// 既存のVirtual Network名
// internal_rag_step_by_step で作成されたVNetを指定してください
param vnetName = 'vnet-internal-rag-dev'

// Container Instance Subnetのアドレスプレフィックス
// 既存のSubnetと重複しないように設定してください
// 注: 10.0.5.0/28 は DNS Private Resolver用に使用されています
param containerSubnetPrefix = '10.0.6.0/24'

// Key Vault名 (グローバルで一意、3-24文字)
// 英数字とハイフンのみ使用可能
param keyVaultName = 'kv-gh-runner-dev'

// 現在のユーザーのオブジェクトID（初期管理者用）
// 以下のコマンドで取得できます:
// az ad signed-in-user show --query id -o tsv
param adminObjectId = 'YOUR_OBJECT_ID_HERE'

// タグ
// すべてのリソースに適用されます
param tags = {
  Environment: 'Development'
  Project: 'GitHub Actions Deployment'
  ManagedBy: 'Bicep'
  CostCenter: 'IT'
}
