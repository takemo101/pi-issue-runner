#!/usr/bin/env bash
# ============================================================================
# list.sh - List active pi-issue-runner sessions
#
# Displays a list of all active tmux sessions created by pi-issue-runner,
# including issue numbers, statuses, and error messages.
#
# Usage: ./scripts/list.sh [options]
#
# Options:
#   -v, --verbose   Show detailed information
#   -h, --help      Show help message
#
# Exit codes:
#   0 - Success
#   1 - Invalid option
#
# Examples:
#   ./scripts/list.sh
#   ./scripts/list.sh -v
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/notify.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    -v, --verbose   詳細情報を表示
    -h, --help      このヘルプを表示
EOF
}

main() {
    local verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                enable_verbose
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
        esac
    done

    load_config

    echo "=== Active Pi Issue Sessions ==="
    echo ""

    local sessions
    sessions="$(list_sessions)"

    if [[ -z "$sessions" ]]; then
        echo "No active sessions found."
        exit 0
    fi

    # ヘッダー表示
    if [[ "$verbose" != "true" ]]; then
        printf "%-20s %-8s %-10s %s\n" "SESSION" "ISSUE" "STATUS" "ERROR"
        printf "%-20s %-8s %-10s %s\n" "-------" "-----" "------" "-----"
    fi

    # セッションごとに情報表示
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        
        # Issue番号を抽出
        local issue_num
        issue_num="${session##*-}"
        
        # ステータス情報を取得
        local status
        status="$(get_status_value "$issue_num")"
        
        # エラーメッセージを取得
        local error_msg
        error_msg="$(get_error_message "$issue_num")"
        [[ -z "$error_msg" ]] && error_msg="-"
        # エラーメッセージを短縮
        if [[ ${#error_msg} -gt 30 ]]; then
            error_msg="${error_msg:0:27}..."
        fi
        
        if [[ "$verbose" == "true" ]]; then
            echo "Session: $session"
            echo "  Issue: #$issue_num"
            echo "  Status: $status"
            
            if [[ "$error_msg" != "-" ]]; then
                echo "  Error: $error_msg"
            fi
            
            # worktree情報
            local worktree
            if worktree="$(find_worktree_by_issue "$issue_num" 2>/dev/null)"; then
                echo "  Worktree: $worktree"
                local branch
                branch="$(get_worktree_branch "$worktree" 2>/dev/null || echo 'unknown')"
                echo "  Branch: $branch"
            fi
            
            # セッション情報
            get_session_info "$session" 2>/dev/null | sed 's/^/  /' || true
            echo ""
        else
            printf "%-20s #%-7s %-10s %s\n" "$session" "$issue_num" "$status" "$error_msg"
        fi
    done <<< "$sessions"
}

main "$@"
