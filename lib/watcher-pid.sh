#!/usr/bin/env bash
# watcher-pid.sh - Watcher PID management
# Extracted from status.sh (Issue #1430)

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_WATCHER_PID_SH_SOURCED:-}" ]]; then
    return 0
fi
_WATCHER_PID_SH_SOURCED="true"

# 自身のディレクトリを取得
_WATCHER_PID_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# status.shの関数（get_status_dir, init_status_dir）に依存
if ! declare -f get_status_dir > /dev/null 2>&1; then
    source "$_WATCHER_PID_LIB_DIR/status.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# =============================================================================
# Watcher PID Management (Issue #693)
# =============================================================================

# Watcher PIDを保存
# 引数:
#   $1 - issue_number: Issue番号
#   $2 - pid: Watcher プロセスID
save_watcher_pid() {
    local issue_number="$1"
    local pid="$2"
    
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local pid_file="${status_dir}/${issue_number}.watcher.pid"
    
    # Atomic write: write to temp file and rename
    local tmp_file="${pid_file}.tmp.$$"
    echo "$pid" > "$tmp_file"
    mv -f "$tmp_file" "$pid_file"
    log_debug "Saved watcher PID for issue #$issue_number: $pid"
}

# Watcher PIDを読み込み
# 引数:
#   $1 - issue_number: Issue番号
# 出力: PID（存在しなければ空）
load_watcher_pid() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local pid_file="${status_dir}/${issue_number}.watcher.pid"
    
    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    fi
}

# Watcher PIDファイルを削除
# 引数:
#   $1 - issue_number: Issue番号
remove_watcher_pid() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local pid_file="${status_dir}/${issue_number}.watcher.pid"
    
    if [[ -f "$pid_file" ]]; then
        rm -f "$pid_file"
        log_debug "Removed watcher PID file for issue #$issue_number"
    fi
}

# Watcherが実行中かチェック
# 引数:
#   $1 - issue_number: Issue番号
# 終了コード: 0 (実行中), 1 (停止中または不明)
is_watcher_running() {
    local issue_number="$1"
    local pid
    pid="$(load_watcher_pid "$issue_number")"
    
    if [[ -z "$pid" ]]; then
        return 1
    fi
    
    # daemon.shのis_daemon_running関数を使用
    # Note: daemon.shがロードされていることを前提とする
    if declare -f is_daemon_running > /dev/null 2>&1; then
        is_daemon_running "$pid"
    else
        # フォールバック: killコマンドでチェック
        kill -0 "$pid" 2>/dev/null
    fi
}
