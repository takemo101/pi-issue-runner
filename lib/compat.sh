#!/usr/bin/env bash
# ============================================================================
# lib/compat.sh - クロスプラットフォーム互換性ヘルパー
#
# macOS と Linux の差異を吸収するユーティリティ関数群。
#
# Provides:
#   - safe_timeout: timeout コマンドのラッパー（macOS互換）
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_COMPAT_SH_SOURCED:-}" ]]; then
    return 0
fi
_COMPAT_SH_SOURCED="true"

# timeout コマンドのラッパー（macOS互換）
# timeout が利用可能ならそのまま使用、なければタイムアウトなしで実行
# Usage: safe_timeout <seconds> <command> [args...]
safe_timeout() {
    local seconds="$1"
    shift
    if command -v timeout &>/dev/null; then
        timeout "$seconds" "$@"
    else
        # タイムアウトなしで実行（macOS標準環境向け）
        "$@"
    fi
}
