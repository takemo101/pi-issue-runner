#!/usr/bin/env bash
# ============================================================================
# restart-watcher.sh - Restart watcher process for a session
#
# Restarts the watch-session.sh watcher daemon for a given tmux session.
# Stops any existing watcher processes and starts a new one.
#
# Usage: ./scripts/restart-watcher.sh <session-name|issue-number>
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   -h, --help      Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error (session not found, watcher failed to start)
#
# Examples:
#   ./scripts/restart-watcher.sh pi-issue-42
#   ./scripts/restart-watcher.sh 42
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
source "$SCRIPT_DIR/../lib/daemon.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/session-resolver.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number>

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -h, --help      このヘルプを表示

Description:
    指定されたセッションのwatcherプロセスを再起動します。
    既存のwatcherが実行中の場合は停止してから新しいwatcherを起動します。

Examples:
    $(basename "$0") pi-issue-42
    $(basename "$0") 42
EOF
}

main() {
    if [[ $# -eq 0 ]]; then
        log_error "Session name or issue number is required"
        usage >&2
        exit 1
    fi

    local target="$1"
    
    # ヘルプオプションのチェック
    if [[ "$target" == "-h" ]] || [[ "$target" == "--help" ]]; then
        usage
        exit 0
    fi

    load_config

    # Issue番号またはセッション名から両方を解決
    local issue_number session_name
    IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "$target")

    # セッション存在確認
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        log_info "Active sessions:"
        mux_list_sessions | sed 's/^/  /'
        exit 1
    fi

    log_info "Restarting watcher for session: $session_name (Issue #$issue_number)"

    # 既存のwatcherを停止（PIDファイルベース）
    local old_pid
    old_pid="$(load_watcher_pid "$issue_number")"
    
    if [[ -n "$old_pid" ]]; then
        if is_daemon_running "$old_pid"; then
            log_info "Stopping existing watcher (PID: $old_pid)..."
            if stop_daemon "$old_pid"; then
                log_debug "Watcher stopped successfully"
            else
                log_warn "Failed to stop watcher via PID, will try pkill"
            fi
            sleep 1
        else
            log_debug "Watcher PID $old_pid is not running (stale PID file)"
        fi
    else
        log_debug "No watcher PID file found"
    fi
    
    # パターンマッチで孤立したwatcherも停止
    log_debug "Checking for orphaned watchers..."
    if pkill -f "watch-session.sh $session_name" 2>/dev/null; then
        log_debug "Stopped orphaned watcher processes"
        sleep 1
    else
        log_debug "No orphaned watchers found"
    fi

    # 新しいwatcherを起動
    local watcher_log="${TMPDIR:-/tmp}/pi-watcher-${session_name}.log"
    local watcher_script="$SCRIPT_DIR/watch-session.sh"
    
    if [[ ! -f "$watcher_script" ]]; then
        log_error "Watcher script not found: $watcher_script"
        exit 1
    fi

    log_info "Starting new watcher..."
    local watcher_pid
    watcher_pid=$(daemonize "$watcher_log" "$watcher_script" "$session_name")
    
    if [[ -z "$watcher_pid" ]] || [[ "$watcher_pid" == "0" ]]; then
        log_error "Failed to start watcher (invalid PID)"
        exit 1
    fi

    # PIDを保存
    save_watcher_pid "$issue_number" "$watcher_pid"

    # 起動確認（1秒待ってプロセスが生きているか確認）
    sleep 1
    if is_daemon_running "$watcher_pid"; then
        log_info "✓ Watcher restarted successfully"
        log_info "  PID: $watcher_pid"
        log_info "  Log: $watcher_log"
        log_info ""
        log_info "To check watcher status:"
        log_info "  ./scripts/status.sh $issue_number"
    else
        log_error "Watcher started but immediately died"
        log_error "Check log file: $watcher_log"
        exit 1
    fi
}

main "$@"
