using './main.bicep'

param location = 'japaneast'
param environmentName = 'dev'
param acrName = 'acrinternalragdev'  // グローバルで一意な名前に変更してください
param vnetName = 'vnet-internal-rag-dev'
param privateEndpointSubnetName = 'snet-private-endpoints'
param acrSku = 'Premium'  // Private LinkにはPremium必須
param enableAdminUser = false  // Managed Identity推奨
param publicNetworkAccess = 'Disabled'  // 本番環境推奨、開発時は'Enabled'も可
