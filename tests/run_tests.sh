#!/usr/bin/env bash
# テスト実行スクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Batsがインストールされているか確認
if ! command -v bats &> /dev/null; then
    echo "Error: bats is not installed" >&2
    echo "Install: brew install bats-core (macOS) or apt install bats (Linux)" >&2
    exit 1
fi

# テスト実行
echo "Running Pi Issue Runner tests..."
echo ""

if [[ $# -gt 0 ]]; then
    # 特定のテストファイルを実行
    bats "$@"
else
    # 全テストを実行
    bats "$SCRIPT_DIR"/{lib,scripts}/*.bats
fi
