#!/usr/bin/env bash
# cleanup.sh - worktree + セッション削除

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

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]
       $(basename "$0") --orphans [--dry-run]
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
    --delete-plans    クローズ済みIssueの計画書を削除
    --rotate-plans    古い計画書を削除（直近N件を保持、設定: plans.keep_recent）
    --all             全てのクリーンアップを実行（--orphans + --rotate-plans）
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
    $(basename "$0") --delete-plans
    $(basename "$0") --delete-plans --dry-run
    $(basename "$0") --rotate-plans         # 古い計画書を削除（直近N件を保持）
    $(basename "$0") --rotate-plans --dry-run
    $(basename "$0") --all                  # 全てのクリーンアップを実行
    $(basename "$0") --all --dry-run        # 削除対象を確認
EOF
}

main() {
    local target=""
    local force=false
    local delete_branch=false
    local keep_session=false
    local keep_worktree=false
    local orphans=false
    local delete_plans=false
    local rotate_plans=false
    local all_cleanup=false
    local age_days=""
    local dry_run=false

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
            --orphans)
                orphans=true
                shift
                ;;
            --delete-plans)
                delete_plans=true
                shift
                ;;
            --rotate-plans)
                rotate_plans=true
                shift
                ;;
            --all)
                all_cleanup=true
                shift
                ;;
            --age)
                if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
                    log_error "--age requires a number of days"
                    usage >&2
                    exit 1
                fi
                age_days="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
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

    load_config

    # --all モード: 全てのクリーンアップを実行
    if [[ "$all_cleanup" == "true" ]]; then
        log_info "=== Full Cleanup ==="
        log_info "Cleaning up orphaned status files..."
        cleanup_orphaned_statuses "$dry_run" "$age_days"
        log_info ""
        log_info "Rotating old plans (keeping recent)..."
        cleanup_old_plans "$dry_run"
        exit 0
    fi

    # --orphans モード: 孤立したステータスファイルのクリーンアップ
    if [[ "$orphans" == "true" ]]; then
        cleanup_orphaned_statuses "$dry_run" "$age_days"
        exit 0
    fi

    # --delete-plans モード: クローズ済みIssueの計画書のクリーンアップ
    if [[ "$delete_plans" == "true" ]]; then
        cleanup_closed_issue_plans "$dry_run"
        exit 0
    fi

    # --rotate-plans モード: 古い計画書のクリーンアップ（直近N件を保持）
    if [[ "$rotate_plans" == "true" ]]; then
        cleanup_old_plans "$dry_run"
        exit 0
    fi

    if [[ -z "$target" ]]; then
        log_error "Session name or issue number is required"
        usage >&2
        exit 1
    fi

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
            
            # ステータスファイルも削除
            log_debug "Removing status file for Issue #$issue_number"
            remove_status "$issue_number"
            
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

    # on_cleanup hookを実行
    run_hook "on_cleanup" "$issue_number" "$session_name" "" "" "" "0" ""
    
    log_info "Cleanup completed."
}

main "$@"
