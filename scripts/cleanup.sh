#!/usr/bin/env bash
# cleanup.sh - worktree + セッション削除

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --force, -f       強制削除（未コミットの変更があっても削除）
    --delete-branch   対応するGitブランチも削除
    --keep-session    セッションを維持（worktreeのみ削除）
    --keep-worktree   worktreeを維持（セッションのみ削除）
    -h, --help        このヘルプを表示

Examples:
    $(basename "$0") pi-issue-42
    $(basename "$0") 42
    $(basename "$0") 42 --force
    $(basename "$0") 42 --delete-branch
EOF
}

main() {
    local target=""
    local force=false
    local delete_branch=false
    local keep_session=false
    local keep_worktree=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            --delete-branch)
                delete_branch=true
                shift
                ;;
            --keep-session)
                keep_session=true
                shift
                ;;
            --keep-worktree)
                keep_worktree=true
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

    load_config

    # Issue番号かセッション名か判定
    local session_name
    local issue_number

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        issue_number="$target"
        session_name="$(generate_session_name "$issue_number")"
    else
        session_name="$target"
        issue_number="$(extract_issue_number "$session_name")"
    fi

    log_info "=== Cleanup ==="
    log_info "Target: $session_name (Issue #$issue_number)"

    # セッション停止
    if [[ "$keep_session" == "false" ]]; then
        if session_exists "$session_name"; then
            log_info "Stopping session: $session_name"
            kill_session "$session_name"
        else
            log_debug "Session not found: $session_name (skipping)"
        fi
    fi

    # Worktree削除
    if [[ "$keep_worktree" == "false" ]]; then
        local worktree
        local branch_name=""
        if worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
            # ブランチ名を取得（削除前に取得する必要がある）
            if [[ "$delete_branch" == "true" ]]; then
                branch_name="$(get_worktree_branch "$worktree")"
            fi
            
            log_info "Removing worktree: $worktree"
            remove_worktree "$worktree" "$force"
            
            # ブランチ削除
            if [[ "$delete_branch" == "true" && -n "$branch_name" ]]; then
                log_info "Deleting branch: $branch_name"
                if ! git branch -d "$branch_name" 2>/dev/null; then
                    if [[ "$force" == "true" ]]; then
                        git branch -D "$branch_name"
                    else
                        log_warn "Branch has unmerged changes. Use --force to delete anyway."
                    fi
                fi
            fi
        else
            log_debug "Worktree not found for Issue #$issue_number (skipping)"
        fi
    fi

    log_info "Cleanup completed."
}

main "$@"
