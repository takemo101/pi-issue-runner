#!/usr/bin/env bash
# ============================================================================
# wait-for-sessions.sh - Wait for multiple sessions to complete
#
# Monitors status files for specified issues and waits until all sessions
# reach a terminal state (complete or error).
#
# Usage: ./scripts/wait-for-sessions.sh <issue-number>... [options]
#
# Arguments:
#   issue-number    One or more GitHub Issue numbers
#
# Options:
#   --interval N    Check interval in seconds (default: 10)
#   --timeout N     Timeout in seconds (default: 0 = no timeout)
#   --quiet         Suppress progress output
#   --fail-fast     Exit immediately when any session has an error
#   --cleanup       Auto-cleanup completed sessions' worktrees
#   -h, --help      Show help message
#
# Exit codes:
#   0 - All sessions completed successfully
#   1 - One or more sessions had errors
#   2 - Timeout reached
#   3 - Invalid arguments
#
# Examples:
#   ./scripts/wait-for-sessions.sh 42 43
#   ./scripts/wait-for-sessions.sh 42 43 --interval 5 --timeout 300
#   ./scripts/wait-for-sessions.sh 42 43 --fail-fast --cleanup
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number>... [options]

Arguments:
    issue-number    One or more GitHub Issue numbers

Options:
    --interval N    Check interval in seconds (default: 10)
    --timeout N     Timeout in seconds (default: 0 = no timeout)
    --quiet         Suppress progress output
    --fail-fast     Exit immediately when any session has an error
    --cleanup       Auto-cleanup completed sessions' worktrees
    -h, --help      Show help message

Exit codes:
    0 - All sessions completed successfully
    1 - One or more sessions had errors
    2 - Timeout reached
    3 - Invalid arguments
EOF
}

# Check if a tmux session exists
check_tmux_session() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

main() {
    local issues=()
    local interval=10
    local timeout_secs=0
    local quiet=false
    local fail_fast=false
    local cleanup=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --timeout)
                timeout_secs="$2"
                shift 2
                ;;
            --quiet)
                quiet=true
                shift
                ;;
            --fail-fast)
                fail_fast=true
                shift
                ;;
            --cleanup)
                cleanup=true
                shift
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                usage >&2
                exit 3
                ;;
            *)
                issues+=("$1")
                shift
                ;;
        esac
    done

    # Validate: at least one issue number required
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "Error: At least one issue number is required" >&2
        usage >&2
        exit 3
    fi

    # Validate: all arguments must be numeric
    for issue in "${issues[@]}"; do
        if ! [[ "$issue" =~ ^[0-9]+$ ]]; then
            echo "Error: Invalid issue number: $issue" >&2
            exit 3
        fi
    done

    # Determine status directory
    local status_dir
    if [[ -n "${PI_RUNNER_WORKTREE_BASE_DIR:-}" ]]; then
        status_dir="${PI_RUNNER_WORKTREE_BASE_DIR}/.status"
    else
        status_dir=".worktrees/.status"
    fi

    if [[ "$cleanup" == "true" && "$quiet" != "true" ]]; then
        echo "Auto-cleanup enabled"
    fi

    local start_time
    start_time=$(date +%s)

    # Monitoring loop
    while true; do
        local all_done=true
        local has_error=false
        local completed_issues=()

        for issue in "${issues[@]}"; do
            local status_file="${status_dir}/${issue}.json"
            local status="unknown"

            if [[ -f "$status_file" ]]; then
                # Extract status from JSON
                if command -v jq &>/dev/null; then
                    status=$(jq -r '.status // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
                else
                    status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$status_file" | sed 's/.*"\([^"]*\)"$/\1/' || echo "unknown")
                fi
            fi

            case "$status" in
                complete)
                    completed_issues+=("$issue")
                    ;;
                error)
                    has_error=true
                    if [[ "$fail_fast" == "true" ]]; then
                        exit 1
                    fi
                    ;;
                running)
                    # Check if tmux session actually exists
                    local session_name="pi-issue-${issue}"
                    # Try to get session name from status file
                    if [[ -f "$status_file" ]] && command -v jq &>/dev/null; then
                        local file_session
                        file_session=$(jq -r '.session // ""' "$status_file" 2>/dev/null || echo "")
                        if [[ -n "$file_session" ]]; then
                            session_name="$file_session"
                        fi
                    fi

                    if ! check_tmux_session "$session_name" 2>/dev/null; then
                        # Session vanished - stale running status
                        echo "Error: セッション消滅 - Issue #${issue} (session: ${session_name})" >&2
                        has_error=true
                        if [[ "$fail_fast" == "true" ]]; then
                            exit 1
                        fi
                    else
                        all_done=false
                    fi
                    ;;
                unknown)
                    # No status file and no tmux session → treat as complete
                    local session_name="pi-issue-${issue}"
                    if check_tmux_session "$session_name" 2>/dev/null; then
                        # Session exists but no status file → still running
                        all_done=false
                    else
                        # No session, no status → treat as complete
                        completed_issues+=("$issue")
                    fi
                    ;;
                *)
                    all_done=false
                    ;;
            esac
        done

        if [[ "$all_done" == "true" || "$has_error" == "true" ]]; then
            # Cleanup if requested
            if [[ "$cleanup" == "true" && ${#completed_issues[@]} -gt 0 ]]; then
                for issue in "${completed_issues[@]}"; do
                    echo "Cleaning up worktree for issue #${issue}"
                    "$SCRIPT_DIR/cleanup.sh" "$issue" 2>/dev/null || true
                done
            fi

            if [[ "$has_error" == "true" ]]; then
                exit 1
            fi
            exit 0
        fi

        # Check timeout
        if [[ "$timeout_secs" -gt 0 ]]; then
            local now
            now=$(date +%s)
            local elapsed=$((now - start_time))
            if [[ "$elapsed" -ge "$timeout_secs" ]]; then
                if [[ "$quiet" != "true" ]]; then
                    echo "Timeout after ${timeout_secs}s" >&2
                fi
                exit 2
            fi
        fi

        if [[ "$quiet" != "true" ]]; then
            echo "Waiting for sessions: ${issues[*]}..."
        fi

        sleep "$interval"
    done
}

main "$@"
