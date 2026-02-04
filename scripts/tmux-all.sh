#!/usr/bin/env bash
# ============================================================================
# tmux-all.sh - Display all pi-issue-runner sessions in tiled view
#
# Two modes:
#   1. Default: Link windows from all sessions (can interact with each)
#   2. Watch mode (-w): Use xpanes to show all sessions simultaneously
#
# Usage: ./scripts/tmux-all.sh [options]
#
# Options:
#   -w, --watch         Watch mode: xpanes tiled view (read-only monitoring)
#   -l, --lines NUM     Lines to show in watch mode (default: 100)
#   -i, --interval SEC  Refresh interval in watch mode (default: 2)
#   -k, --kill          Kill existing monitor session first
#   -h, --help          Show help message
#
# Examples:
#   ./scripts/tmux-all.sh           # Link all sessions as windows
#   ./scripts/tmux-all.sh -w        # xpanes tiled view
#   ./scripts/tmux-all.sh -k        # Restart monitor session
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

MONITOR_SESSION="pi-monitor"
KILL_EXISTING=false
WATCH_MODE=false
LINES=100
INTERVAL=2
ALL_SESSIONS=false
PREFIX=""

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

全てのpi-issue-runnerセッションを表示します。

モード:
    デフォルト          各セッションをウィンドウとしてリンク（操作可能）
    -w, --watch         xpanesでタイル表示（監視専用、全セッション同時表示）

Options:
    -a, --all           全ての *-issue-* セッションを対象（プレフィックス無視）
    -p, --prefix NAME   特定のプレフィックスを指定（例: dict）
    -w, --watch         ウォッチモード（xpanesでタイル表示）
    -l, --lines NUM     表示行数（ウォッチモード用、default: 100）
    -i, --interval SEC  更新間隔（ウォッチモード用、default: 2）
    -k, --kill          既存のモニターセッションを削除して再作成
    -h, --help          このヘルプを表示

キー操作（デフォルトモード）:
    Ctrl+b n            次のセッション
    Ctrl+b p            前のセッション
    Ctrl+b w            セッション一覧
    Ctrl+b d            デタッチ

Examples:
    $(basename "$0") -a -w          # 全 *-issue-* セッションをxpanesで表示
    $(basename "$0") -p dict -w     # dict-issue-* セッションを表示
    $(basename "$0") -w             # 設定のプレフィックスで表示
    $(basename "$0") -k             # 再作成して表示
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                ALL_SESSIONS=true
                shift
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -w|--watch)
                WATCH_MODE=true
                shift
                ;;
            -l|--lines)
                LINES="$2"
                shift 2
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -k|--kill)
                KILL_EXISTING=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                shift
                ;;
        esac
    done

    check_tmux || exit 1
    load_config

    # Get sessions based on options (exclude pi-monitor)
    local sessions
    if [[ "$ALL_SESSIONS" == "true" ]]; then
        # All *-issue-* sessions
        sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -- "-issue-" | grep -v "^pi-monitor" || true)
    elif [[ -n "$PREFIX" ]]; then
        # Specific prefix
        sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${PREFIX}-issue-" | grep -v "^pi-monitor" || true)
    else
        # Use config prefix
        sessions=$(list_sessions | grep -v "^pi-monitor" || true)
    fi

    if [[ -z "$sessions" ]]; then
        log_warn "No active pi-issue-runner sessions found"
        exit 0
    fi

    local session_count
    session_count=$(echo "$sessions" | wc -l | tr -d ' ')
    log_info "Found $session_count session(s)"

    # Watch mode: use xpanes to attach to all sessions
    if [[ "$WATCH_MODE" == "true" ]]; then
        if ! command -v xpanes &> /dev/null; then
            log_error "xpanes is not installed"
            log_info "Install with: brew install xpanes"
            exit 1
        fi

        # Convert to array
        local session_array=()
        while IFS= read -r session; do
            [[ -n "$session" ]] && session_array+=("$session")
        done <<< "$sessions"

        log_info "Opening ${#session_array[@]} sessions in xpanes..."
        log_info "Press Ctrl+b d to detach from individual pane"
        
        # TMUX='' allows nested tmux attach
        xpanes -t -c "TMUX='' tmux attach-session -t {}" "${session_array[@]}"
        exit 0
    fi

    # Default mode: link windows
    # Kill existing monitor session if requested or exists
    if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
        if [[ "$KILL_EXISTING" == "true" ]]; then
            log_info "Killing existing monitor session..."
            tmux kill-session -t "$MONITOR_SESSION"
        else
            log_info "Attaching to existing monitor session..."
            log_info "Use -k to recreate"
            tmux attach-session -t "$MONITOR_SESSION"
            exit 0
        fi
    fi

    # Create new monitor session with first target session linked
    local first_session
    first_session=$(echo "$sessions" | head -1)
    
    log_info "Creating monitor session: $MONITOR_SESSION"
    
    # Create monitor session grouped with first target session
    tmux new-session -d -s "$MONITOR_SESSION" -t "$first_session"
    
    # Link remaining sessions as windows
    local count=1
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        [[ "$session" == "$first_session" ]] && continue
        
        count=$((count + 1))
        log_debug "Linking session: $session"
        tmux link-window -s "$session" -t "$MONITOR_SESSION:$count"
    done <<< "$sessions"

    # Attach to monitor session
    log_info "Attached. Use Ctrl+b w for window list, Ctrl+b d to detach"
    tmux attach-session -t "$MONITOR_SESSION"
}

main "$@"
