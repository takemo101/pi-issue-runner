#!/usr/bin/env bash
# ============================================================================
# mux-all.sh - Display all pi-issue-runner sessions in tiled view
#
# Supports both tmux and Zellij multiplexers.
#
# Modes:
#   tmux:   Default uses link-window, watch mode uses xpanes
#   zellij: Uses native panes (no xpanes required)
#
# Usage: ./scripts/mux-all.sh [options]
#
# Options:
#   -a, --all           All *-issue-* sessions (ignore prefix)
#   -p, --prefix NAME   Specific prefix (e.g., dict)
#   -w, --watch         Watch mode: tmux uses xpanes, zellij uses native panes
#   -k, --kill          Kill existing monitor session first
#   -h, --help          Show help message
#
# Examples:
#   ./scripts/mux-all.sh           # Show all sessions
#   ./scripts/mux-all.sh -k        # Recreate monitor session
#   ./scripts/mux-all.sh -a        # All *-issue-* sessions
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
# multiplexer.sh is loaded via tmux.sh, providing mux_* functions

MONITOR_SESSION="pi-monitor"
KILL_EXISTING=false
WATCH_MODE=false
ALL_SESSIONS=false
PREFIX=""

usage() {
    load_config
    local mux_type
    mux_type="$(get_config multiplexer_type)"
    mux_type="${mux_type:-tmux}"
    
    cat << EOF
Usage: $(basename "$0") [options]

全てのpi-issue-runnerセッションを表示します。
現在のマルチプレクサ: ${mux_type:-tmux}

モード:
    デフォルト          tmux: link-window / zellij: ネイティブペイン
    -w, --watch         tmux: xpanesでタイル表示 / zellij: ネイティブペイン

Options:
    -a, --all           全ての *-issue-* セッションを対象
    -p, --prefix NAME   特定のプレフィックスを指定（例: dict）
    -w, --watch         ウォッチモード（tmux: xpanes / zellij: 同上）
    -k, --kill          既存のモニターセッションを削除して再作成
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") -a             # 全セッションを表示
    $(basename "$0") -p dict        # dict-issue-* セッションを表示
    $(basename "$0") -k             # モニターセッションを再作成
EOF
}

# tmux用: セッション一覧を取得
list_tmux_sessions() {
    local prefix="$1"
    local all="$2"
    
    if [[ "$all" == "true" ]]; then
        # NOTE: -a/--all モードでは設定済みプレフィックスに関わらず全 *-issue-* セッションを
        # 返す必要があるため、mux_list_sessions（プレフィックスフィルタ付き）ではなく
        # tmux list-sessions を直接使用している
        tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -- "-issue-" | grep -v "^pi-monitor" || true
    elif [[ -n "$prefix" ]]; then
        # NOTE: -p/--prefix モードでは任意のプレフィックスを指定できるため、
        # mux_list_sessions（設定プレフィックス固定）ではなく直接フィルタリング
        tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${prefix}-issue-" | grep -v "^pi-monitor" || true
    else
        # デフォルト: 抽象化レイヤー経由でセッション一覧を取得
        mux_list_sessions | grep -v "^pi-monitor" || true
    fi
}

# zellij用: セッション一覧を取得
list_zellij_sessions() {
    local prefix="$1"
    local all="$2"
    
    local all_sessions
    all_sessions=$(zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}' || true)
    
    if [[ "$all" == "true" ]]; then
        echo "$all_sessions" | grep -- "-issue-" | grep -v "^pi-monitor" || true
    elif [[ -n "$prefix" ]]; then
        echo "$all_sessions" | grep "^${prefix}-issue-" | grep -v "^pi-monitor" || true
    else
        echo "$all_sessions" | grep "^$(get_config multiplexer_session_prefix)" | grep -v "^pi-monitor" || true
    fi
}

# xpanesでセッションを表示（tmux用）
show_with_xpanes_tmux() {
    local -a session_array=("$@")
    
    log_info "Opening ${#session_array[@]} sessions in xpanes..."
    log_info "Press Ctrl+b d to detach"
    
    # TMUX='' allows nested tmux attach
    xpanes -t -c "TMUX='' tmux attach-session -t {}" "${session_array[@]}"
}

# tmux: link-windowモード
tmux_link_mode() {
    local sessions="$1"
    
    # Kill existing monitor session if requested
    if mux_session_exists "$MONITOR_SESSION"; then
        if [[ "$KILL_EXISTING" == "true" ]]; then
            log_info "Killing existing monitor session..."
            mux_kill_session "$MONITOR_SESSION" 10
        else
            log_info "Attaching to existing monitor session..."
            log_info "Use -k to recreate"
            mux_attach_session "$MONITOR_SESSION"
            return 0
        fi
    fi

    local first_session
    first_session=$(echo "$sessions" | head -1)
    
    log_info "Creating monitor session: $MONITOR_SESSION"
    
    # NOTE: 以下は tmux 固有の操作（セッショングループ化 + link-window）
    # mux_create_session はコマンド実行用のため、ここでは -t オプションで
    # 既存セッションとグループ化する tmux 固有APIを直接使用する
    tmux new-session -d -s "$MONITOR_SESSION" -t "$first_session"
    
    # Link remaining sessions as windows
    # NOTE: link-window は tmux 固有の機能（他セッションのウィンドウを参照リンク）
    # マルチプレクサ抽象化レイヤーには該当する汎用APIが存在しない
    local count=1
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        [[ "$session" == "$first_session" ]] && continue
        
        count=$((count + 1))
        log_debug "Linking session: $session"
        tmux link-window -s "$session" -t "$MONITOR_SESSION:$count"
    done <<< "$sessions"

    log_info "Attached. Use Ctrl+b w for window list, Ctrl+b d to detach"
    mux_attach_session "$MONITOR_SESSION"
}

# zellij: ネイティブペインモード（xpanes不要）
zellij_native_mode() {
    local sessions="$1"
    
    # Convert to array
    local session_array=()
    while IFS= read -r session; do
        [[ -n "$session" ]] && session_array+=("$session")
    done <<< "$sessions"
    
    local session_count=${#session_array[@]}
    
    if [[ $session_count -eq 1 ]]; then
        # Single session: direct attach
        log_info "Attaching to session: ${session_array[0]}"
        zellij attach "${session_array[0]}"
        return
    fi
    
    # Multiple sessions: use native Zellij panes
    log_info "Opening $session_count sessions in Zellij panes..."
    
    # Kill existing monitor session if requested
    if zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$MONITOR_SESSION "; then
        if [[ "$KILL_EXISTING" == "true" ]]; then
            log_info "Killing existing monitor session..."
            zellij delete-session "$MONITOR_SESSION" --force 2>/dev/null || true
            sleep 1
        else
            log_info "Attaching to existing monitor session..."
            log_info "Use -k to recreate"
            zellij attach "$MONITOR_SESSION"
            return
        fi
    fi
    
    # Create monitor session and attach to first target session
    log_info "Creating monitor session: $MONITOR_SESSION"
    
    # Start monitor session with first attach command
    local first_session="${session_array[0]}"
    
    # Create session in background
    nohup zellij -s "$MONITOR_SESSION" </dev/null >/dev/null 2>&1 &
    
    # Wait for session to be ready
    local waited=0
    while ! zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$MONITOR_SESSION " && [[ "$waited" -lt 10 ]]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    
    if ! zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$MONITOR_SESSION "; then
        log_error "Failed to create monitor session"
        exit 1
    fi
    
    sleep 1
    
    # Setup first pane with attach to first session
    ZELLIJ_SESSION_NAME="$MONITOR_SESSION" zellij action write-chars "ZELLIJ='' zellij attach '$first_session'" 2>/dev/null || true
    ZELLIJ_SESSION_NAME="$MONITOR_SESSION" zellij action write 13 2>/dev/null || true
    
    # Add remaining sessions as new panes
    local i
    for ((i = 1; i < session_count; i++)); do
        local target_session="${session_array[$i]}"
        
        sleep 0.3
        
        # Create new pane (splits current pane)
        ZELLIJ_SESSION_NAME="$MONITOR_SESSION" zellij action new-pane --direction down 2>/dev/null || \
        ZELLIJ_SESSION_NAME="$MONITOR_SESSION" zellij action new-pane 2>/dev/null || true
        
        sleep 0.3
        
        # Attach to target session in new pane
        ZELLIJ_SESSION_NAME="$MONITOR_SESSION" zellij action write-chars "ZELLIJ='' zellij attach '$target_session'" 2>/dev/null || true
        ZELLIJ_SESSION_NAME="$MONITOR_SESSION" zellij action write 13 2>/dev/null || true
    done
    
    # Auto-layout for even distribution
    sleep 0.5
    
    log_info "Press Ctrl+o d to detach from monitor session"
    log_info "Press Ctrl+o Tab to switch between panes"
    
    # Attach to monitor session
    zellij attach "$MONITOR_SESSION"
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

    load_config
    local mux_type
    mux_type="$(get_config multiplexer_type)"
    mux_type="${mux_type:-tmux}"
    
    # Check multiplexer
    mux_check || exit 1

    # Get sessions based on multiplexer type
    local sessions
    case "$mux_type" in
        tmux)
            sessions=$(list_tmux_sessions "$PREFIX" "$ALL_SESSIONS")
            ;;
        zellij)
            sessions=$(list_zellij_sessions "$PREFIX" "$ALL_SESSIONS")
            ;;
        *)
            log_error "Unknown multiplexer type: $mux_type"
            exit 1
            ;;
    esac

    if [[ -z "$sessions" ]]; then
        log_warn "No active pi-issue-runner sessions found"
        exit 0
    fi

    local session_count
    session_count=$(echo "$sessions" | wc -l | tr -d ' ')
    log_info "Found $session_count session(s) [$mux_type]"

    # Convert to array for xpanes
    local session_array=()
    while IFS= read -r session; do
        [[ -n "$session" ]] && session_array+=("$session")
    done <<< "$sessions"

    # Watch mode
    if [[ "$WATCH_MODE" == "true" ]]; then
        case "$mux_type" in
            tmux)
                if ! command -v xpanes &> /dev/null; then
                    log_error "xpanes is not installed"
                    log_info "Install with: brew install xpanes"
                    exit 1
                fi
                show_with_xpanes_tmux "${session_array[@]}"
                ;;
            zellij)
                # Zellijはネイティブペイン機能を使用（デフォルトと同じ）
                zellij_native_mode "$sessions"
                ;;
        esac
        exit 0
    fi

    # Default mode
    case "$mux_type" in
        tmux)
            tmux_link_mode "$sessions"
            ;;
        zellij)
            zellij_native_mode "$sessions"
            ;;
    esac
}

main "$@"
