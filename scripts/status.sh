#!/usr/bin/env bash
# status.sh - タスク状態確認

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --output N      セッション出力の最新N行を表示（デフォルト: 20）
    -h, --help      このヘルプを表示
EOF
}

main() {
    local target=""
    local output_lines=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|-o)
                output_lines="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$target" ]]; then
        echo "Error: Session name or issue number is required" >&2
        usage >&2
        exit 1
    fi

    load_config

    # Issue番号かセッション名か判定
    local session_name
    local issue_number

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # Issue番号
        issue_number="$target"
        session_name="$(generate_session_name "$issue_number")"
    else
        # セッション名
        session_name="$target"
        issue_number="$(extract_issue_number "$session_name")"
    fi

    echo "=== Task Status ==="
    echo ""
    
    # Issue情報
    echo "--- Issue ---"
    echo "Number: #$issue_number"
    local title
    title="$(get_issue_title "$issue_number" 2>/dev/null || echo 'Unable to fetch')"
    echo "Title: $title"
    local state
    state="$(get_issue_state "$issue_number" 2>/dev/null || echo 'Unknown')"
    echo "State: $state"
    echo ""

    # セッション情報
    echo "--- Session ---"
    echo "Name: $session_name"
    if session_exists "$session_name"; then
        echo "Status: Running"
        get_session_info "$session_name" 2>/dev/null || true
    else
        echo "Status: Not running"
    fi
    echo ""

    # Worktree情報
    echo "--- Worktree ---"
    local worktree
    if worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
        echo "Path: $worktree"
        local branch
        branch="$(get_worktree_branch "$worktree" 2>/dev/null || echo 'unknown')"
        echo "Branch: $branch"
        
        # Git status
        if [[ -d "$worktree" ]]; then
            echo "Git Status:"
            (cd "$worktree" && git status --short 2>/dev/null | head -10 | sed 's/^/  /')
        fi
    else
        echo "Not found"
    fi
    echo ""

    # セッション出力
    if session_exists "$session_name"; then
        echo "--- Recent Output (last $output_lines lines) ---"
        get_session_output "$session_name" "$output_lines" 2>/dev/null || echo "Unable to capture output"
    fi
}

main "$@"
