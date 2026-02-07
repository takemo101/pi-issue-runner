#!/usr/bin/env bash
# ============================================================================
# status.sh - Check task status
#
# Displays detailed status information for a pi-issue-runner session,
# including issue details, session state, worktree path, and recent output.
#
# Usage: ./scripts/status.sh <session-name|issue-number> [options]
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   --output N      Show last N lines of session output (default: 20)
#   -h, --help      Show help message
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments or options
#
# Examples:
#   ./scripts/status.sh pi-issue-42
#   ./scripts/status.sh 42
#   ./scripts/status.sh 42 --output 50
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/session-resolver.sh"

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
                log_error "Unknown option: $1"
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
        log_error "Session name or issue number is required"
        usage >&2
        exit 1
    fi

    load_config

    # Issue番号またはセッション名から両方を解決
    local issue_number session_name
    IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "$target")

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

    # Watcher情報 (Issue #693)
    echo "--- Watcher ---"
    local watcher_pid
    watcher_pid="$(load_watcher_pid "$issue_number" 2>/dev/null || echo '')"
    
    if [[ -n "$watcher_pid" ]]; then
        if is_watcher_running "$issue_number"; then
            echo "Status: Running (PID: $watcher_pid)"
            local watcher_log="/tmp/pi-watcher-${session_name}.log"
            echo "Log: $watcher_log"
        else
            echo "Status: Not running ⚠️"
            echo "Hint: Run 'scripts/restart-watcher.sh $issue_number' to restart"
        fi
    else
        echo "Status: No watcher found"
        if session_exists "$session_name"; then
            echo "Hint: Run 'scripts/restart-watcher.sh $issue_number' to start"
        fi
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
