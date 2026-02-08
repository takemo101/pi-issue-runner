#!/usr/bin/env bash
# ============================================================================
# cleanup.sh - Cleanup worktree and session
#
# Removes worktrees and stops tmux sessions created by pi-issue-runner.
# Supports various cleanup modes including orphan cleanup and batch operations.
#
# Usage: ./scripts/cleanup.sh <session-name|issue-number> [options]
#        ./scripts/cleanup.sh --orphans [--dry-run]
#        ./scripts/cleanup.sh --all [--dry-run]
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   --force, -f         Force removal (even with uncommitted changes)
#   --delete-branch     Also delete the corresponding Git branch
#   --keep-session      Keep the session (remove worktree only)
#   --keep-worktree     Keep the worktree (stop session only)
#   --orphans           Clean up orphaned status files
#   --orphan-worktrees  Clean up worktrees with 'complete' status
#   --delete-plans      Delete plans for closed issues
#   --rotate-plans      Rotate old plans (keep recent N)
#   --improve-logs      Clean up .improve-logs directory
#   --all               Run all cleanup operations
#   --age <days>        Delete status files older than N days
#   --dry-run           Show what would be deleted without deleting
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/cleanup.sh pi-issue-42
#   ./scripts/cleanup.sh 42
#   ./scripts/cleanup.sh --orphans
#   ./scripts/cleanup.sh --all --dry-run
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/hooks.sh"
source "$SCRIPT_DIR/../lib/cleanup-plans.sh"
source "$SCRIPT_DIR/../lib/cleanup-orphans.sh"
source "$SCRIPT_DIR/../lib/cleanup-improve-logs.sh"
source "$SCRIPT_DIR/../lib/session-resolver.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]
       $(basename "$0") --orphans [--dry-run]
       $(basename "$0") --orphan-worktrees [--dry-run] [--force]
       $(basename "$0") --all [--dry-run]

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --force, -f       強制削除（未コミットの変更があっても削除）
    --delete-branch   対応するGitブランチも削除
    --keep-session    セッションを維持（worktreeのみ削除）
    --keep-worktree   worktreeを維持（セッションのみ削除）
    --orphans         孤立したステータスファイルをクリーンアップ
    --orphan-worktrees  complete状態だがworktreeが残存しているケースをクリーンアップ
    --delete-plans    クローズ済みIssueの計画書を削除
    --rotate-plans    古い計画書を削除（直近N件を保持、設定: plans.keep_recent）
    --improve-logs    .improve-logsディレクトリをクリーンアップ
    --all             全てのクリーンアップを実行（--orphans + --rotate-plans + --orphan-worktrees + --improve-logs）
    --age <days>      指定日数より古いステータスファイルを削除（--orphansと併用）
    --dry-run         削除せずに対象を表示（--orphans/--delete-plans/--rotate-plans/--allと使用）
    -h, --help        このヘルプを表示

Examples:
    $(basename "$0") pi-issue-42
    $(basename "$0") 42
    $(basename "$0") 42 --force
    $(basename "$0") 42 --delete-branch
    $(basename "$0") --orphans
    $(basename "$0") --orphans --dry-run
    $(basename "$0") --orphans --age 7      # 孤立かつ7日以上前のファイルを削除
    $(basename "$0") --orphan-worktrees      # complete状態の残存worktreeを削除
    $(basename "$0") --orphan-worktrees --force
    $(basename "$0") --delete-plans
    $(basename "$0") --delete-plans --dry-run
    $(basename "$0") --rotate-plans         # 古い計画書を削除（直近N件を保持）
    $(basename "$0") --rotate-plans --dry-run
    $(basename "$0") --improve-logs         # improve-logsをクリーンアップ
    $(basename "$0") --improve-logs --age 7 # 7日以上前のログを削除
    $(basename "$0") --improve-logs --dry-run
    $(basename "$0") --all                  # 全てのクリーンアップを実行
    $(basename "$0") --all --dry-run        # 削除対象を確認
EOF
}

# Parse command line arguments
parse_cleanup_arguments() {
    local -n _target_ref=$1
    local -n _force_ref=$2
    local -n _delete_branch_ref=$3
    local -n _keep_session_ref=$4
    local -n _keep_worktree_ref=$5
    local -n _orphans_ref=$6
    local -n _orphan_worktrees_ref=$7
    local -n _delete_plans_ref=$8
    local -n _rotate_plans_ref=$9
    local -n _improve_logs_ref=${10}
    local -n _all_cleanup_ref=${11}
    local -n _age_days_ref=${12}
    local -n _dry_run_ref=${13}
    shift 13
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                _force_ref=true
                shift
                ;;
            --delete-branch)
                _delete_branch_ref=true
                shift
                ;;
            --keep-session)
                _keep_session_ref=true
                shift
                ;;
            --keep-worktree)
                _keep_worktree_ref=true
                shift
                ;;
            --orphans)
                _orphans_ref=true
                shift
                ;;
            --orphan-worktrees)
                _orphan_worktrees_ref=true
                shift
                ;;
            --delete-plans)
                _delete_plans_ref=true
                shift
                ;;
            --rotate-plans)
                _rotate_plans_ref=true
                shift
                ;;
            --improve-logs)
                _improve_logs_ref=true
                shift
                ;;
            --all)
                _all_cleanup_ref=true
                shift
                ;;
            --age)
                if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
                    log_error "--age requires a number of days"
                    usage >&2
                    exit 1
                fi
                _age_days_ref="$2"
                shift 2
                ;;
            --dry-run)
                _dry_run_ref=true
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
                _target_ref="$1"
                shift
                ;;
        esac
    done
}

# Execute all cleanup operations
execute_all_cleanup() {
    local dry_run="$1"
    local age_days="$2"
    local force="$3"
    
    log_info "=== Full Cleanup ==="
    log_info "Cleaning up orphaned status files..."
    cleanup_orphaned_statuses "$dry_run" "$age_days"
    log_info ""
    log_info "Cleaning up orphaned worktrees with 'complete' status..."
    cleanup_complete_with_worktrees "$dry_run" "$force"
    log_info ""
    log_info "Rotating old plans (keeping recent)..."
    cleanup_old_plans "$dry_run"
    log_info ""
    log_info "Cleaning up improve-logs..."
    cleanup_improve_logs "$dry_run" "$age_days"
}

# Execute single issue cleanup
execute_single_cleanup() {
    local target="$1"
    local force="$2"
    local delete_branch="$3"
    local keep_session="$4"
    local keep_worktree="$5"
    
    # Issue番号またはセッション名から両方を解決
    local issue_number session_name
    IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "$target")

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
    local cleanup_failed=false
    local worktree=""
    local branch_name=""
    
    if [[ "$keep_worktree" == "false" ]]; then
        if worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
            # ブランチ名を取得（削除前に取得する必要がある）
            if [[ "$delete_branch" == "true" ]]; then
                branch_name="$(get_worktree_branch "$worktree" 2>/dev/null)" || {
                    log_warn "Could not determine branch name for worktree: $worktree"
                    branch_name=""
                }
            fi
            
            log_info "Removing worktree: $worktree"
            if ! safe_remove_worktree "$worktree" "$force"; then
                log_error "Failed to remove worktree: $worktree"
                cleanup_failed=true
            else
                log_info "Worktree removed successfully"
            fi
            
            # ブランチ削除
            if [[ "$delete_branch" == "true" && -n "$branch_name" ]]; then
                log_info "Deleting branch: $branch_name"
                if ! git branch -d "$branch_name" 2>/dev/null; then
                    if [[ "$force" == "true" ]]; then
                        log_info "Force deleting branch: $branch_name"
                        if ! git branch -D "$branch_name" 2>/dev/null; then
                            log_warn "Failed to delete branch: $branch_name"
                            cleanup_failed=true
                        fi
                    else
                        log_warn "Branch has unmerged changes. Use --force to delete anyway."
                    fi
                else
                    log_info "Branch deleted successfully: $branch_name"
                fi
            fi
        else
            log_debug "Worktree not found for Issue #$issue_number (skipping)"
        fi
        
        # ステータスファイルも削除（worktreeの有無に関わらず）
        log_debug "Removing status file for Issue #$issue_number"
        remove_status "$issue_number" || {
            log_warn "Failed to remove status file for Issue #$issue_number"
        }
        
        # Watcher PIDファイルも削除 (Issue #693)
        log_debug "Removing watcher PID file for Issue #$issue_number"
        remove_watcher_pid "$issue_number" || {
            log_warn "Failed to remove watcher PID file for Issue #$issue_number"
        }
        
        # Watcher ログファイルも削除 (Issue #1068)
        local watcher_log="/tmp/pi-watcher-${session_name}.log"
        if [[ -f "$watcher_log" ]]; then
            log_debug "Removing watcher log file: $watcher_log"
            rm -f "$watcher_log" 2>/dev/null || {
                log_warn "Failed to remove watcher log file: $watcher_log"
            }
        fi
    fi

    # on_cleanup hookを実行（失敗しても後続処理を継続）
    log_debug "Running on_cleanup hook..."
    run_hook "on_cleanup" "$issue_number" "$session_name" "$branch_name" "$worktree" "" "0" "" || {
        log_warn "on_cleanup hook failed, but continuing cleanup process"
    }
    
    if [[ "$cleanup_failed" == "true" ]]; then
        log_error "Cleanup completed with errors for Issue #$issue_number"
        log_error "Some resources may still remain. Check logs above for details."
        return 1
    fi
    
    log_info "Cleanup completed successfully for Issue #$issue_number"
}

main() {
    local target=""
    local force=false
    local delete_branch=false
    local keep_session=false
    local keep_worktree=false
    local orphans=false
    local orphan_worktrees=false
    local delete_plans=false
    local rotate_plans=false
    local improve_logs=false
    local all_cleanup=false
    local age_days=""
    local dry_run=false

    # Parse command line arguments
    parse_cleanup_arguments \
        target force delete_branch keep_session keep_worktree \
        orphans orphan_worktrees delete_plans rotate_plans improve_logs \
        all_cleanup age_days dry_run \
        "$@"

    load_config

    # Execute appropriate cleanup mode
    if [[ "$all_cleanup" == "true" ]]; then
        execute_all_cleanup "$dry_run" "$age_days" "$force"
        exit 0
    fi

    if [[ "$orphans" == "true" ]]; then
        cleanup_orphaned_statuses "$dry_run" "$age_days"
        exit 0
    fi

    if [[ "$orphan_worktrees" == "true" ]]; then
        cleanup_complete_with_worktrees "$dry_run" "$force"
        exit 0
    fi

    if [[ "$delete_plans" == "true" ]]; then
        cleanup_closed_issue_plans "$dry_run"
        exit 0
    fi

    if [[ "$rotate_plans" == "true" ]]; then
        cleanup_old_plans "$dry_run"
        exit 0
    fi

    if [[ "$improve_logs" == "true" ]]; then
        cleanup_improve_logs "$dry_run" "$age_days"
        exit 0
    fi

    # Single issue cleanup mode
    if [[ -z "$target" ]]; then
        log_error "Session name or issue number is required"
        usage >&2
        exit 1
    fi

    execute_single_cleanup "$target" "$force" "$delete_branch" "$keep_session" "$keep_worktree"
}

main "$@"
