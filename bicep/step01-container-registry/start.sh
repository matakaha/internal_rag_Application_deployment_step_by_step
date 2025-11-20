#!/bin/bash
set -e

# デバッグ情報
echo "=== GitHub Runner Startup ==="
echo "Runner Name: ${RUNNER_NAME:-runner-$(hostname)}"
echo "Repository URL: ${RUNNER_REPOSITORY_URL}"
echo "Work Directory: ${RUNNER_WORK_DIRECTORY:-_work}"
echo "Labels: ${RUNNER_LABELS:-self-hosted}"

# ネットワーク接続テスト
echo "=== Network Connectivity Test ==="
if curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://github.com | grep -q "200\|301\|302"; then
    echo "✅ GitHub.com is reachable"
else
    echo "❌ Cannot reach GitHub.com"
    echo "Testing DNS resolution..."
    nslookup github.com || echo "DNS resolution failed"
    exit 1
fi

# 必須環境変数チェック
if [ -z "$RUNNER_TOKEN" ] || [ -z "$RUNNER_REPOSITORY_URL" ]; then
    echo "❌ Error: RUNNER_TOKEN and RUNNER_REPOSITORY_URL must be set"
    exit 1
fi

echo "=== Configuring GitHub Runner ==="
./config.sh \
    --url "${RUNNER_REPOSITORY_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME:-runner-$(hostname)}" \
    --work "${RUNNER_WORK_DIRECTORY:-_work}" \
    --labels "${RUNNER_LABELS:-self-hosted}" \
    --unattended \
    --replace

echo "=== Starting GitHub Runner ==="
./run.sh
