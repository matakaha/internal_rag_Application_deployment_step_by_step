# Microsoft公式のGitHub Actions Runnerイメージを使用
FROM mcr.microsoft.com/dotnet/runtime-deps:6.0

# 必要なパッケージのインストール
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Azure CLIのインストール
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# GitHub Actions Runnerのダウンロードとインストール
ARG RUNNER_VERSION=2.311.0
WORKDIR /actions-runner
RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && ./bin/installdependencies.sh

# 起動スクリプトをコピー
COPY start.sh /actions-runner/start.sh
RUN chmod +x /actions-runner/start.sh

# エントリーポイント
ENTRYPOINT ["/actions-runner/start.sh"]
