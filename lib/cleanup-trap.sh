#!/usr/bin/env bash
# cleanup-trap.sh - エラー時のクリーンアップトラップ管理

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CLEANUP_TRAP_SH_SOURCED:-}" ]]; then
    return 0
fi
_CLEANUP_TRAP_SH_SOURCED="true"

# 現在のディレクトリを取得
_CLEANUP_TRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# logを読み込み
source "$_CLEANUP_TRAP_LIB_DIR/log.sh"

# エラー時のクリーンアップハンドラを設定
# 使用例: setup_cleanup_trap "cleanup_function"
_CLEANUP_FUNC=""

setup_cleanup_trap() {
    _CLEANUP_FUNC="${1:-}"
    trap '_cleanup_handler' EXIT
}

_cleanup_handler() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with code $exit_code"
        if [[ -n "${_CLEANUP_FUNC:-}" ]] && declare -f "$_CLEANUP_FUNC" > /dev/null 2>&1; then
            log_debug "Running cleanup function: $_CLEANUP_FUNC"
            "$_CLEANUP_FUNC" || true
        fi
    fi
}

# worktree作成時のクリーンアップ用
# グローバル変数 _WORKTREE_TO_CLEANUP に設定されたパスを削除
cleanup_worktree_on_error() {
    if [[ -n "${_WORKTREE_TO_CLEANUP:-}" && -d "$_WORKTREE_TO_CLEANUP" ]]; then
        log_warn "Cleaning up incomplete worktree: $_WORKTREE_TO_CLEANUP"
        git worktree remove --force "$_WORKTREE_TO_CLEANUP" 2>/dev/null || true
        unset _WORKTREE_TO_CLEANUP
    fi
}

# worktreeパスを記録（エラー時クリーンアップ用）
register_worktree_for_cleanup() {
    _WORKTREE_TO_CLEANUP="$1"
}

# クリーンアップ対象から除外（成功時に呼び出す）
unregister_worktree_for_cleanup() {
    unset _WORKTREE_TO_CLEANUP
}
