# Microsoft公式のUbuntuイメージを使用
FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

# 必要なパッケージをインストール (.NET 6.0依存関係、Python 3.11、Node.js含む)
RUN tdnf install -y \
    ca-certificates \
    curl \
    tar \
    gzip \
    jq \
    git \
    shadow-utils \
    icu \
    python3 \
    python3-pip \
    python3-devel \
    nodejs \
    npm \
    zip \
    unzip \
    && tdnf clean all


# Azure CLIをpipでインストール (CBL Mariner 2.0用リポジトリが利用不可のため)
# azure-coreを最新にアップグレードして依存関係の問題を解決
# システムグローバルにインストールして、すべてのユーザーで共有
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools && \
    python3 -m pip install --no-cache-dir --upgrade azure-core azure-mgmt-core && \
    python3 -m pip install --no-cache-dir azure-cli

# Pythonのシンボリックリンク作成
RUN ln -sf /usr/bin/python3 /usr/bin/python

# GitHub Runner用の非rootユーザーを作成
RUN useradd -m -s /bin/bash runner

# runnerユーザーがローカルpipインストールを行わないようPYTHONUSERBASEを無効化
# システムグローバルのパッケージを優先使用
ENV PYTHONNOUSERSITE=1 \
    PIP_NO_USER=1

# GitHub Runnerをインストール
ARG RUNNER_VERSION=2.311.0
WORKDIR /actions-runner

RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && chown -R runner:runner /actions-runner

# 起動スクリプトをコピー
COPY start.sh /actions-runner/start.sh
RUN chmod +x /actions-runner/start.sh

# 起動スクリプトをコピー
COPY start.sh /start.sh
RUN chmod +x /start.sh

# 非rootユーザーに切り替え
USER runner

ENTRYPOINT ["/start.sh"]
