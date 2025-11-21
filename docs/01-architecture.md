# アーキテクチャ概要

このドキュメントでは、GitHub ActionsでAzure閉域環境（vNet統合済Web Apps)へCI/CDデプロイする際のアーキテクチャについて説明します。

## 前提環境

このガイドは、[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)で構築した以下の環境を前提としています:

### 既存のリソース

| リソース | 名前例 | 用途 |
|---------|-------|------|
| Virtual Network | `vnet-internal-rag-dev` | 閉域ネットワーク基盤 |
| NAT Gateway | `natgw-internal-rag-dev` | アウトバウンド通信用固定 Public IP |
| Private Endpoint Subnet | `snet-private-endpoints` | Private Endpoint配置 |
| App Integration Subnet | `snet-app-integration` | Web Apps vNet統合 |
| Compute Subnet | `snet-compute` | 将来の拡張用 |
| Web Apps | `app-internal-rag-dev` | アプリケーション実行環境 |
| Private DNS Zones | 複数 | Private Endpoint名前解決 |

## CI/CDアーキテクチャ

### 概要図

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GitHub (パブリック環境)                               │
│                                                                          │
│  ┌──────────────────┐                                                   │
│  │  GitHub Actions  │                                                   │
│  │  Workflow        │                                                   │
│  └────────┬─────────┘                                                   │
│           │                                                              │
└───────────┼──────────────────────────────────────────────────────────────┘
            │
            │ 1. ACI起動リクエスト (az container start)
            │    ※ACRへの接続は不要!
            │
┌───────────▼──────────────────────────────────────────────────────────────┐
│               Azure Virtual Network (10.0.0.0/16)                        │
│                                                                           │
│  ┌───────────────────────────────────────────────────────────────┐       │
│  │      Azure Container Registry (ACR) - Step 01                 │       │
│  │                                                                │       │
│  │  ┌──────────────────────────────────────────────────┐        │       │
│  │  │ ネットワークルール:                              │        │       │
│  │  │ - NAT Gateway Public IP 許可                     │        │       │
│  │  └──────────────────────────────────────────────────┘        │       │
│  │                                                                │       │
│  │  - 事前ビルド済GitHub Runnerイメージ                          │       │
│  │  - Private Endpoint経由でアクセス                             │       │
│  │  - 完全閉域（パブリック公開不要）                             │       │
│  └───────────────────┬───────────────────────────────────────────┘       │
│                      │ GitHub Actionsワークフローで動的にACIを作成      │
│  ┌──────────────────▼───────────────────────────────────────┐           │
│  │          Container Instance Subnet (10.0.6.0/24) - Step 02  │       │
│  │                                                                │       │
│  │  ┌─────────────────────────────────────────────────────┐    │       │
│  │  │  Azure Container Instance (動的作成)                │    │       │
│  │  │  (Self-hosted GitHub Actions Runner)                │    │       │
│  │  │                                                       │    │       │
│  │  │  - ACRからイメージプル済（Private Endpoint経由）    │    │       │
│  │  │  - GitHub Actionsから起動/停止のみ制御              │    │       │
│  │  │  - GitHub Runner登録                                │    │       │
│  │  │  - Key Vaultからシークレット取得                    │    │       │
│  │  │  - アプリケーションビルド                            │    │       │
│  │  │  - Web Appsへデプロイ                               │    │       │
│  │  └───────────┬─────────────────────────────────────────┘    │       │
│  │              │                                                │       │
│  │              │ アウトバウンド通信                            │       │
│  │              ▼                                                │       │
│  │      ┌───────────────────┐                                   │       │
│  │      │   NAT Gateway     │                                   │       │
│  │      │ (固定 Public IP)  │                                   │       │
│  │      └───────────────────┘                                   │       │
│  │                                                                │       │
│  └────────────────────────────────────────────────────────────────┘       │
│                 │                                                         │
│                 │ 2. シークレット取得                                     │
│                 │                                                         │
│  ┌──────────────▼─────────────┐     ┌────────────────────────┐         │
│  │      Key Vault - Step 03   │     │      Web Apps          │         │
│  │                            │     │  (vNet統合済)          │         │
│  │  - デプロイ用認証情報      │     │                        │         │
│  │  - 接続文字列              │     │  - アプリ実行          │         │
│  │  - APIキー                 │     │  - Private Endpoint    │         │
│  │                            │     │    経由でアクセス      │         │
│  │  Private Endpoint          │     │                        │         │
│  └────────────────────────────┘     └───────────┬────────────┘         │
│                 ▲                                │                       │
│                 │                                │ 3. デプロイ           │
│                 │                                │                       │
│  ┌──────────────┴────────────────────────────────▼─────────────┐       │
│  │            Private Endpoint Subnet (10.0.1.0/24)            │       │
│  │                                                               │       │
│  │  - Key Vault Private Endpoint                                │       │
│  │  - ACR Private Endpoint                                      │       │
│  │  - その他サービスのPrivate Endpoint                          │       │
│  └───────────────────────────────────────────────────────────────┘       │
│                                                                           │
│  ┌───────────────────────────────────────────────────────────────┐       │
│  │         App Integration Subnet (10.0.2.0/24)                 │       │
│  │         (Web Apps vNet統合)                                   │       │
│  └───────────────────────────────────────────────────────────────┘       │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

## デプロイフロー

### 1. 全体フロー図

```mermaid
sequenceDiagram
    participant Dev as 開発者
    participant GH as GitHub
    participant ACR as Container Registry<br/>(Private Endpoint)
    participant ACI as Container Instance<br/>(Self-hosted Runner)
    participant KV as Key Vault<br/>(Private Endpoint)
    participant App as Web Apps<br/>(vNet統合)

    Note over Dev,App: 事前準備: ACRにRunnerイメージをビルド済み

    Dev->>GH: git push (main branch)
    GH->>GH: Workflow開始 (ubuntu-latest)
    GH->>ACI: Azure CLIでContainer Instance作成<br/>vNetサブネット指定
    ACI->>ACR: Runnerイメージをプル<br/>(Private Endpoint経由、完全閉域)
    ACR-->>ACI: イメージ返却
    ACI->>GH: Self-hosted Runnerとして登録
    
    Note over ACI: Self-hosted Runnerジョブ開始
    
    ACI->>KV: Azure認証情報取得<br/>(Private Endpoint経由)
    KV-->>ACI: CLIENT_ID, TENANT_ID等を返却
    ACI->>ACI: アプリケーションコードビルド
    ACI->>App: Publish Profileでデプロイ<br/>(vNet経由、閉域通信)
    App-->>ACI: デプロイ完了
    ACI->>GH: ジョブ完了報告
    
    GH->>ACI: Container Instance削除<br/>(コスト最適化)
```

### 2. 詳細ステップ解説

#### Step 1: ACR構築（事前準備）
**目的**: Self-hosted Runnerコンテナーイメージの事前ビルドと格納

**手順**:
1. Azure Container Registry (ACR) を Premium SKU で作成
2. ACR用 Private Endpoint を設定（完全閉域化）
3. NAT Gateway の Public IP を ACR ファイアウォールに登録
4. ACR Tasks でRunnerイメージをビルド（ローカルDocker不要）
5. ビルドしたイメージをACRに格納

**メリット**:
- ✅ Container Instance起動時にインターネット接続不要
- ✅ 完全閉域環境でRunner実行可能
- ✅ NAT Gateway経由でACR Tasksが実行可能（パブリック公開不要）
- ✅ イメージバージョン管理が容易

#### Step 2: Workflow起動トリガー
**トリガー方法**:
- `main`ブランチへの`git push`
- Pull Requestのマージ
- 手動トリガー (`workflow_dispatch`)
- スケジュール実行 (`schedule`)

**実行環境**: GitHub-hosted Runner (`ubuntu-latest`) で初期ジョブを実行

#### Step 3: Container Instance起動
**実行内容**:
1. Azure CLI で Container Instance を動的作成
2. ACRからRunnerイメージをプル（Private Endpoint経由、完全閉域）
3. vNet統合Subnet (`snet-container-instances`) に配置
4. 環境変数でGitHubリポジトリ情報を渡す
5. 起動スクリプトがGitHub Runnerを自動登録

**セキュリティポイント**:
- vNet内部からのみアクセス可能
- NSGで通信を制限
- インターネット接続は最小限（GitHub API通信のみHTTPS 443）

#### Step 4: シークレット取得
**実行内容**:
1. Container Instance の Managed Identity で Key Vault に認証
2. Azure認証情報（OIDC用: CLIENT_ID, TENANT_ID, SUBSCRIPTION_ID）を取得
3. 必要に応じてPublish Profile等を取得
4. 環境変数として設定

**認証方式の違い**:

| 項目 | OIDC認証（推奨） | Client Secret方式 |
|------|-----------------|------------------|
| **シークレット数** | 3個（ID系のみ） | 4個（パスワード含む） |
| **セキュリティ** | ✅ 高（一時トークン） | ⚠️ 中（長期パスワード） |
| **管理負担** | ✅ 低（ローテーション不要） | ⚠️ 高（定期ローテーション） |
| **推奨度** | ✅ 本番環境推奨 | △ テスト環境のみ |

#### Step 5: ビルド・デプロイ
**実行内容**:
1. アプリケーションコードのチェックアウト
2. 依存関係のインストール（npm, pip等）
3. アプリケーションのビルド
4. Web Apps / Azure Functions へデプロイ（vNet経由）
5. デプロイ結果の確認

**通信経路**: すべてvNet内部で完結（Private Endpoint経由）

#### Step 6: クリーンアップ
**実行内容**:
1. GitHub API経由でSelf-hosted Runnerの登録解除
2. Azure CLI で Container Instance を削除
3. リソース削除の確認

**コスト最適化**:
- Container Instanceは使用時のみ課金
- ジョブ完了後即座に削除で無駄なコスト削減

## コンポーネント詳細

### Azure Container Registry (ACR) - Step 01

#### 概要
- **SKU**: Premium（Private Link対応のため必須）
- **用途**: GitHub Actions RunnerのDockerイメージ格納
- **アクセス**: Private Endpoint経由のみ（パブリックアクセス無効）
- **ネットワークルール**: NAT Gateway の Public IP を許可リストに追加

#### セキュリティ
- Private Endpoint統合でvNet内からのみアクセス可能
- Managed Identity認証推奨
- イメージスキャン機能で脆弱性検出
- **NAT Gateway 統合**: ACR Tasks が固定 Public IP 経由でアクセス可能

#### メリット
- **完全閉域**: Container Instance起動時にインターネット接続不要
- **高速起動**: ローカルネットワーク経由でイメージプル
- **安定性**: 外部サービスの障害影響を排除
- **バージョン管理**: タグによるイメージバージョン管理
- **NAT Gateway 統合のメリット**:
  - ✅ ACR Tasks でのビルド時にパブリックアクセス有効化が不要
  - ✅ セキュリティ強化（ACR のパブリックアクセスを常に無効化）
  - ✅ 手順簡素化（ビルドのたびに有効化/無効化が不要）
  - ✅ 完全な閉域環境（固定 Public IP のみ許可）

#### イメージ管理
- **ベースイメージ**: Microsoft公式イメージ使用
- **タグ戦略**: `latest`（開発）、`1.x.x`（本番）
- **更新フロー**: ローカルビルド → テスト → ACRプッシュ

### Container Instance Subnet (新規追加)

#### 概要
- **アドレス範囲**: 10.0.6.0/24
- **用途**: Self-hosted GitHub Actions Runnerの実行環境
- **特徴**: 都度起動・削除でコスト最適化

#### セキュリティ
- NSGでアクセス制御
- vNet内部からのみアクセス可能
- パブリックIPなし

### Key Vault

#### 概要
- **目的**: デプロイ用認証情報の安全な管理
- **アクセス**: Private Endpoint経由のみ
- **認証**: マネージドID

#### 格納する情報
- Web Appsデプロイ用サービスプリンシパル
- 接続文字列
- APIキー
- その他シークレット

#### アクセス制御
- Container InstanceのマネージドIDに権限付与
- 最小権限の原則を適用
- アクセスログ監視

### Self-hosted Runner

#### 選択理由
- vNet内リソースへの直接アクセスが必要
- GitHub ホステッドRunnerではPrivate Endpointへアクセス不可
- セキュリティ要件を満たすため

#### 実装方式
- **Container Instance**: 都度起動・削除
- **メリット**: 
  - コスト効率が良い（使用時のみ課金）
  - 最新の環境を毎回構築
  - メンテナンス不要
- **デメリット**:
  - 起動時間がかかる（約2-3分）

#### 代替案との比較

| 方式 | メリット | デメリット | コスト |
|------|---------|-----------|--------|
| **Container Instance** | 都度起動、最新環境 | 起動遅い | ¥1,000〜3,000/月 |
| VM (常時起動) | 高速起動 | 常時課金、メンテナンス必要 | ¥10,000〜/月 |
| Azure DevOps Agent | Azure統合良好 | GitHub Actions使えない | - |

## セキュリティ設計

### ネットワークセキュリティ

#### Private Endpoint
- すべての通信をvNet内に閉じ込め
- パブリックアクセス無効化
- Private DNS Zone統合

#### NSG
- サブネットごとに適切な制御
- 最小権限の原則
- ログ監視

### 認証・認可

#### マネージドID
- Container InstanceにシステムマネージドID付与
- Key VaultへのアクセスはマネージドIDで認証
- パスワード不要

#### サービスプリンシパル
- Web Appsデプロイ用
- Key Vaultで安全に管理
- 定期的なローテーション推奨

### シークレット管理

#### Key Vault
- すべてのシークレットをKey Vaultで一元管理
- アクセス監査ログ有効化
- 自動ローテーション機能の活用

#### GitHub Secrets
- Key Vault接続情報のみ格納
- 環境ごとに分離
- 最小限の情報のみ

## 運用設計

### デプロイ頻度

- **開発環境**: 1日数回〜数十回
- **Container Instance**: 使用時のみ起動でコスト最適化
- **想定起動時間**: デプロイあたり5〜10分

### モニタリング

#### Container Instance
- Azure Monitorでログ収集
- デプロイ成功/失敗の追跡
- リソース使用状況監視

#### Key Vault
- アクセスログ監視
- 異常なアクセスパターン検知
- 監査証跡の保持

#### Web Apps
- Application Insights統合
- デプロイ履歴追跡
- パフォーマンス監視

### コスト最適化

#### Container Instance
- ジョブ完了後即座に削除
- 適切なリソースサイズ選定
- 同時実行数の制御

#### Key Vault
- Standard SKU使用
- 不要なシークレットの定期削除
- アクセス頻度の監視

## 拡張性

### 複数環境対応

```
├── Dev環境
│   ├── Container Instance
│   ├── Key Vault (dev)
│   └── Web Apps (dev)
├── Staging環境
│   ├── Container Instance
│   ├── Key Vault (stg)
│   └── Web Apps (stg)
└── Production環境
    ├── Container Instance
    ├── Key Vault (prod)
    └── Web Apps (prod)
```

### スケーリング

- Runner並列実行数の調整
- Container Instanceリソースサイズ変更
- vNetアドレス範囲の拡張

## ベストプラクティス

### Infrastructure as Code
- すべてのインフラをBicepで管理
- バージョン管理
- 環境ごとのパラメータ分離

### GitOps
- main/developブランチ保護
- Pull Requestによるレビュー
- 自動テスト実行

### セキュリティ
- 最小権限の原則
- シークレットのローテーション
- 監査ログの保持

### コスト管理
- 不要なリソースの削除
- 適切なSKU選定
- コストアラート設定

## 次のステップ

アーキテクチャを理解したら、実際にデプロイを開始しましょう:

- [デプロイガイド](deployment-guide.md)
- [Step 02: Container Instance Subnet追加](../bicep/step02-runner-subnet/README.md)
