#!/usr/bin/env bash
# ============================================================================
# mux-all.sh - Display all pi-issue-runner sessions in tiled view
#
# Supports both tmux and Zellij multiplexers.
#
# Two modes:
#   1. Default: Link windows (tmux) or use xpanes (zellij)
#   2. Watch mode (-w): Use xpanes to show all sessions simultaneously
#
# Usage: ./scripts/mux-all.sh [options]
#
# Options:
#   -a, --all           All *-issue-* sessions (ignore prefix)
#   -p, --prefix NAME   Specific prefix (e.g., dict)
#   -w, --watch         Watch mode: xpanes tiled view
#   -k, --kill          Kill existing monitor session first
#   -h, --help          Show help message
#
# Examples:
#   ./scripts/mux-all.sh           # Show all sessions
#   ./scripts/mux-all.sh -w        # xpanes tiled view
#   ./scripts/mux-all.sh -a -w     # All *-issue-* sessions
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

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
    デフォルト          tmux: link-window / zellij: xpanes
    -w, --watch         xpanesでタイル表示（両方対応）

Options:
    -a, --all           全ての *-issue-* セッションを対象
    -p, --prefix NAME   特定のプレフィックスを指定（例: dict）
    -w, --watch         ウォッチモード（xpanesでタイル表示）
    -k, --kill          既存のモニターセッションを削除して再作成
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") -a -w          # 全セッションをxpanesで表示
    $(basename "$0") -p dict -w     # dict-issue-* セッションを表示
    $(basename "$0") -w             # 設定のプレフィックスで表示
EOF
}

# tmux用: セッション一覧を取得
list_tmux_sessions() {
    local prefix="$1"
    local all="$2"
    
    if [[ "$all" == "true" ]]; then
        tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -- "-issue-" | grep -v "^pi-monitor" || true
    elif [[ -n "$prefix" ]]; then
        tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${prefix}-issue-" | grep -v "^pi-monitor" || true
    else
        list_sessions | grep -v "^pi-monitor" || true
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
        echo "$all_sessions" | grep "^$(get_config tmux_session_prefix)" | grep -v "^pi-monitor" || true
    fi
}

# xpanesでセッションを表示（tmux用）
show_with_xpanes_tmux() {
    local -a session_array=("$@")
    
    log_info "Opening ${#session_array[@]} sessions in xpanes..."
    log_info "Press Ctrl+b d to detach"
    log_info "Tip: Press Ctrl+b then 'E' to equalize pane sizes"
    
    # TMUX='' allows nested tmux attach
    # -l t: tiled layout for equal-sized panes
    # -d: desync mode (allow independent input to each pane)
    xpanes -t -l t -d -c "TMUX='' tmux attach-session -t {}" "${session_array[@]}"
}

# xpanesでセッションを表示（zellij用）
show_with_xpanes_zellij() {
    local -a session_array=("$@")
    
    log_info "Opening ${#session_array[@]} sessions in xpanes..."
    log_info "Press Ctrl+o d to detach from Zellij"
    log_info "Tip: Press Ctrl+b then 'E' to equalize pane sizes"
    
    # ZELLIJ='' allows nested zellij attach
    # -l t: tiled layout for equal-sized panes
    # -d: desync mode (allow independent input to each pane)
    xpanes -t -l t -d -c "ZELLIJ='' zellij attach {}" "${session_array[@]}"
}

# tmux: link-windowモード
tmux_link_mode() {
    local sessions="$1"
    
    # Kill existing monitor session if requested
    if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
        if [[ "$KILL_EXISTING" == "true" ]]; then
            log_info "Killing existing monitor session..."
            tmux kill-session -t "$MONITOR_SESSION"
        else
            log_info "Attaching to existing monitor session..."
            log_info "Use -k to recreate"
            tmux attach-session -t "$MONITOR_SESSION"
            return 0
        fi
    fi

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

    log_info "Attached. Use Ctrl+b w for window list, Ctrl+b d to detach"
    tmux attach-session -t "$MONITOR_SESSION"
}

# Zellijレイアウトを生成
generate_zellij_layout() {
    local -a sessions=("$@")
    local count=${#sessions[@]}
    
    # レイアウト開始
    echo "layout {"
    
    if [[ "$count" -le 2 ]]; then
        # 2つ以下: 横並び
        echo '    pane split_direction="vertical" {'
        for session in "${sessions[@]}"; do
            cat << EOF
        pane command="bash" {
            args "-c" "ZELLIJ='' zellij attach '$session'"
        }
EOF
        done
        echo '    }'
    elif [[ "$count" -le 4 ]]; then
        # 3-4つ: 2x2グリッド
        echo '    pane split_direction="horizontal" {'
        echo '        pane split_direction="vertical" {'
        for session in "${sessions[@]:0:2}"; do
            cat << EOF
            pane command="bash" {
                args "-c" "ZELLIJ='' zellij attach '$session'"
            }
EOF
        done
        echo '        }'
        echo '        pane split_direction="vertical" {'
        for session in "${sessions[@]:2}"; do
            cat << EOF
            pane command="bash" {
                args "-c" "ZELLIJ='' zellij attach '$session'"
            }
EOF
        done
        echo '        }'
        echo '    }'
    else
        # 5つ以上: 縦に並べる
        echo '    pane split_direction="horizontal" {'
        for session in "${sessions[@]}"; do
            cat << EOF
        pane command="bash" {
            args "-c" "ZELLIJ='' zellij attach '$session'"
        }
EOF
        done
        echo '    }'
    fi
    
    echo "}"
}

# zellij: デフォルトモード（ネイティブレイアウト使用）
zellij_default_mode() {
    local sessions="$1"
    
    # Convert to array
    local session_array=()
    while IFS= read -r session; do
        [[ -n "$session" ]] && session_array+=("$session")
    done <<< "$sessions"
    
    if [[ ${#session_array[@]} -eq 1 ]]; then
        # Single session: direct attach
        log_info "Attaching to session: ${session_array[0]}"
        zellij attach "${session_array[0]}"
        return
    fi
    
    # 既存のモニターセッションをチェック
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
    
    # Multiple sessions: use Zellij native layout
    local layout_file
    layout_file=$(mktemp /tmp/zellij-layout-XXXXXX.kdl)
    
    generate_zellij_layout "${session_array[@]}" > "$layout_file"
    
    log_info "Opening ${#session_array[@]} sessions with Zellij layout..."
    log_debug "Layout file: $layout_file"
    log_info "Press Ctrl+q to quit monitor session"
    
    # 新しいZellijセッションをレイアウトで開始
    ZELLIJ='' zellij --layout "$layout_file" --session "$MONITOR_SESSION"
    
    # クリーンアップ
    rm -f "$layout_file"
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
    check_tmux || exit 1

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
                # Zellijはネイティブレイアウトを使用（デフォルトと同じ）
                zellij_default_mode "$sessions"
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
            zellij_default_mode "$sessions"
            ;;
    esac
}

main "$@"
