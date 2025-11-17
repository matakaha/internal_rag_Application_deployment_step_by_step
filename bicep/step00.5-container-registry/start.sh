#!/bin/bash
set -e

# 必須環境変数の確認
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN is not set"
    exit 1
fi

if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "Error: GITHUB_REPOSITORY is not set"
    exit 1
fi

# Runner登録トークンの取得
REGISTRATION_TOKEN=$(curl -sX POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token" \
    | jq -r .token)

# Runnerの設定
./config.sh \
    --url "https://github.com/${GITHUB_REPOSITORY}" \
    --token "${REGISTRATION_TOKEN}" \
    --name "azure-runner-$(hostname)" \
    --labels "azure,self-hosted" \
    --unattended \
    --ephemeral

# Runnerの起動
./run.sh
