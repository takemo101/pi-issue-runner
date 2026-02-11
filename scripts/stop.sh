#!/usr/bin/env bash
# ============================================================================
# stop.sh - Stop a running session
#
# Terminates a pi-issue-runner session by session name or issue number.
# Optionally cleans up worktree, branch, and closes the issue.
#
# Usage: ./scripts/stop.sh <session-name|issue-number> [options]
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   --cleanup           Stop session + remove worktree/branch
#   --close-issue       Also close the GitHub Issue (use with --cleanup)
#   --force, -f         Force removal (even with uncommitted changes)
#   --delete-branch     Also delete the corresponding Git branch
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Session stopped successfully
#   1 - Session not found or error occurred
#
# Examples:
#   ./scripts/stop.sh pi-issue-42
#   ./scripts/stop.sh 42
#   ./scripts/stop.sh 42 --cleanup
#   ./scripts/stop.sh 42 --cleanup --close-issue
#   ./scripts/stop.sh 42 --cleanup --force
#   ./scripts/stop.sh 42 --cleanup --delete-branch
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
source "$SCRIPT_DIR/../lib/session-resolver.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --cleanup           セッション停止 + worktree/ブランチ削除
    --close-issue       Issueもクローズ（--cleanup と併用）
    --force, -f         強制削除（未コミットの変更があっても削除）
    --delete-branch     対応するGitブランチも削除
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") pi-issue-42
    $(basename "$0") 42
    $(basename "$0") 42 --cleanup
    $(basename "$0") 42 --cleanup --close-issue
    $(basename "$0") 42 --cleanup --force
    $(basename "$0") 42 --cleanup --delete-branch
EOF
}

main() {
    local target=""
    local do_cleanup=false
    local close_issue=false
    local force=false
    local delete_branch=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cleanup)
                do_cleanup=true
                shift
                ;;
            --close-issue)
                close_issue=true
                shift
                ;;
            --force|-f)
                force=true
                shift
                ;;
            --delete-branch)
                delete_branch=true
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

    require_config_file "pi-stop" || exit 1
    load_config

    # Issue番号またはセッション名から両方を解決
    local issue_number session_name
    IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "$target")

    # セッション停止
    mux_kill_session "$session_name"
    log_info "Session stopped: $session_name"

    # --cleanup: worktree/ブランチ削除 + tracker記録
    if [[ "$do_cleanup" == "true" ]]; then
        log_info "Running cleanup for Issue #$issue_number..."

        # tracker に "abandoned" として記録
        source "$SCRIPT_DIR/../lib/tracker.sh"
        record_tracker_entry "$issue_number" "abandoned" 2>/dev/null || true

        # ステータスを "abandoned" に設定
        source "$SCRIPT_DIR/../lib/status.sh"
        set_status "$issue_number" "abandoned"

        # cleanup.sh を呼び出し（worktree/ブランチ削除）
        local cleanup_args=("$target")
        if [[ "$force" == "true" ]]; then
            cleanup_args+=("--force")
        fi
        if [[ "$delete_branch" == "true" ]]; then
            cleanup_args+=("--delete-branch")
        fi
        # セッションは既に停止済みなので --keep-session を指定
        cleanup_args+=("--keep-session")

        "$SCRIPT_DIR/cleanup.sh" "${cleanup_args[@]}"

        # --close-issue: GitHub Issueをクローズ
        if [[ "$close_issue" == "true" ]]; then
            if [[ -n "$issue_number" ]] && command -v gh &>/dev/null; then
                log_info "Closing Issue #$issue_number..."
                if gh issue close "$issue_number" --comment "Closed via stop.sh --cleanup --close-issue" 2>/dev/null; then
                    log_info "Issue #$issue_number closed"
                else
                    log_warn "Failed to close Issue #$issue_number"
                fi
            else
                log_warn "Cannot close issue: gh command not available or issue number unknown"
            fi
        fi

        log_info "Cleanup completed for Issue #$issue_number"
    fi
}

main "$@"
