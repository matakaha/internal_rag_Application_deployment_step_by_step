# Azure 閉域Web Apps GitHub Actions デプロイ Step by Step ガイド

GitHub ActionsでAzure閉域環境（vNet統合済Web Apps）へCI/CDデプロイする方法を、段階的に学べる教材です。

## 📚 概要

このリポジトリは、[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)で構築した閉域環境に対して、GitHub Actionsを使ってアプリケーションをデプロイする方法を学ぶための教材です。

### 特徴

- ✅ **Step by Step**: 各ステップが独立しており、段階的に学習できる
- ✅ **閉域対応**: vNet統合済Web AppsへのCI/CDデプロイを実現
- ✅ **Self-hosted Runner**: Azure Container Instanceを使ったセキュアなRunner構成
- ✅ **Key Vault統合**: 認証情報の安全な管理
- ✅ **ベストプラクティス**: Azureのセキュリティ・運用ベストプラクティスに準拠

## 🏗️ アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│          Azure Virtual Network (10.0.0.0/16)               │
│                                                             │
│  ┌──────────────────┐     ┌──────────────────┐            │
│  │ Container Registry│     │   Key Vault      │            │
│  │   (ACR + PE)     │     │  (認証情報管理)   │            │
│  └────────┬─────────┘     └────────┬─────────┘            │
│           │                        │                       │
│           │ Private Endpoint       │ Private Endpoint      │
│           │                        │                       │
│  ┌────────┴────────────────────────┴─────────┐            │
│  │  Container Instance Subnet (10.0.6.0/24)  │            │
│  │    (Self-hosted GitHub Actions Runner)    │            │
│  │    ← ACRからイメージプル(完全閉域)        │            │
│  └───────────────┬───────────────────────────┘            │
│                  │                                         │
│                  │ vNet Integration                        │
│                  │                                         │
│    ┌─────────────▼───────────┐                            │
│    │  Azure Functions        │                            │
│    │  (Flex Consumption)     │                            │
│    │  バックエンドAPI         │                            │
│    └─────────────────────────┘                            │
│           │                                                │
│           │ Private Endpoint                               │
│           ▼                                                │
│    ┌──────────────────┐     ┌──────────────────┐          │
│    │  App Service     │     │ Azure OpenAI     │          │
│    │  (Node.js/Express)     │ AI Search        │          │
│    │  フロントエンド   │     └──────────────────┘          │
│    └──────────────────┘                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                       │
                       │ GitHub Actions
                       │ (パブリック)
                       ▼
              ┌─────────────────┐
              │  GitHub         │
              │  Repository     │
              └─────────────────┘
```

## 🚀 クイックスタート

> **📘 初めての方へ**: まず [前提条件](docs/00-prerequisites.md) を確認し、必要な環境とツールが揃っているか確認してください。

### 前提条件

- [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)の環境が構築済みであること
  - Virtual Network (vNet)
  - Private DNS Zones
  - App Service (vNet統合済、フロントエンド用)
  - Azure Functions (Flex Consumption, vNet統合済、バックエンド用)
- Azure CLI (`az --version`)
- Bicep CLI (`az bicep version`)
- GitHub アカウント
- Azure サブスクリプション（共同作成者権限）

詳細は [前提条件](docs/00-prerequisites.md) を参照してください。

### デプロイ手順

```powershell
# 1. リポジトリのクローン
git clone https://github.com/matakaha/internal_rag_Application_deployment_step_by_step.git
cd internal_rag_Application_deployment_step_by_step

# 2. リソースグループの確認（既存の環境を使用）
$RESOURCE_GROUP = "rg-internal-rag-dev"
$LOCATION = "japaneast"

# 3. Step 01から順番にデプロイ
cd bicep/step01-container-registry
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters parameters.bicepparam
```

詳細な手順は [デプロイガイド](docs/deployment-guide.md) を参照してください。

## 📖 学習ステップ

### Step 01: Azure Container Registryの構築 [→](bicep/step01-container-registry/)
- ACRの作成とPrivate Endpoint統合
- GitHub Actions RunnerのDockerイメージビルド
- 完全閉域環境でのコンテナー実行

### Step 02: Self-hosted Runner用Subnet追加 [→](bicep/step02-runner-subnet/)
- Container Instance用サブネット追加
- NSG設定
- 既存vNetへの統合

### Step 03: Container Instance構築 [→](bicep/step03-container-instance/)
- Self-hosted Runner用ACIの事前作成
- ACRからのイメージプル(Private Endpoint経由)
- Managed Identity認証
- ACR Pull権限の付与

### Step 04: Key Vault構築 [→](bicep/step04-keyvault/)
- Key Vaultの作成
- Private Endpoint設定
- アクセスポリシー設定
- デプロイ用認証情報の格納

### Step 05: GitHub Actions Workflow [→](bicep/step05-github-actions/)
- OIDC認証(Federated Credential)による安全な認証
- GitHub Secretsの設定方法
- サンプルアプリケーションリポジトリの利用ガイド
- Self-hosted Runnerの仕組み理解
- CI/CDパイプラインの構築

> **📦 実際のアプリケーション**: [internal_rag_Application_sample_repo](https://github.com/matakaha/internal_rag_Application_sample_repo) で完全なRAGアプリ(Node.js + Azure Functions)を提供

### 統合デプロイ [→](bicep/complete/)
全ステップを一括でデプロイする統合版

## 📚 ドキュメント

- [前提条件](docs/00-prerequisites.md) - 必要なツール、サービスプリンシパル作成、GitHub PAT取得など
- [アーキテクチャ概要](docs/01-architecture.md) - システム構成と設計思想
- [デプロイガイド](docs/deployment-guide.md) - ステップバイステップのデプロイ手順

## 💰 コスト

このアーキテクチャの月額概算コスト: **¥7,000〜12,000** (既存環境に追加)

| リソース | SKU/プラン | 月額概算 |
|---------|-----------|---------|
| Azure Container Registry | Premium | ¥6,000 |
| Key Vault | Standard | ¥500 |
| Container Instances | 1vCPU/1.5GB (都度起動) | ¥1,000〜3,000 |
| Private Endpoint | 3個 | ¥3,000 |

> **💡 ヒント**: 
> - Container Instancesは使用時のみ課金されます。デプロイ頻度に応じてコストが変動します。
> - ACRのPremium SKUはPrivate Link対応に必須ですが、完全閉域環境を実現できます。
> - 後続のアプリケーションリポジトリでは、App Service (フロントエンド)とAzure Functions (バックエンド)のコストが追加されます。

## 🛠️ トラブルシューティング

問題が発生した場合:
1. [デプロイガイド - トラブルシューティング](docs/deployment-guide.md#トラブルシューティング) を確認
2. [Issues](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/issues) で既存の問題を検索
3. 新しいIssueを作成

## 🤝 コントリビューション

改善提案やバグ報告は Issue または Pull Request でお願いします。

## 📄 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照してください。

## 🔗 参考リンク

- [GitHub Actions Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Azure Container Instances](https://learn.microsoft.com/ja-jp/azure/container-instances/)
- [Azure Key Vault](https://learn.microsoft.com/ja-jp/azure/key-vault/)
- [Azure App Service](https://learn.microsoft.com/ja-jp/azure/app-service/)
- [GitHub ActionsでAzure App Serviceにデプロイ](https://learn.microsoft.com/ja-jp/azure/app-service/deploy-github-actions)
