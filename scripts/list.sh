#!/usr/bin/env bash
# list.sh - 実行中セッション一覧

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"

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
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
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

    # セッションごとに情報表示
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        
        # Issue番号を抽出
        local issue_num
        issue_num="${session##*-}"
        
        if [[ "$verbose" == "true" ]]; then
            echo "Session: $session"
            echo "  Issue: #$issue_num"
            
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
            printf "%-20s Issue #%-6s\n" "$session" "$issue_num"
        fi
    done <<< "$sessions"
}

main "$@"
