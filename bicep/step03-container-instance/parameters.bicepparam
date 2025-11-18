using './main.bicep'

param location = 'japaneast'
param environmentName = 'dev'
param vnetName = 'vnet-internal-rag-dev'
param containerSubnetName = 'snet-container-instances'
param acrName = 'acrinternalragdev'  // Step 01で作成したACR名
param containerInstanceName = 'aci-github-runner-dev'
param runnerImageTag = 'latest'
param cpuCores = 2
param memoryInGb = 4
