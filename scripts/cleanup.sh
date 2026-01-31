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
    --all             全てのクリーンアップを実行（--orphans + --delete-plans）
    --age <days>      指定日数より古いステータスファイルを削除（--orphansと併用）
    --dry-run         削除せずに対象を表示（--orphans/--delete-plans/--allと使用）
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
    $(basename "$0") --all                  # 全てのクリーンアップを実行
    $(basename "$0") --all --dry-run        # 削除対象を確認
EOF
}

# クローズ済みIssueの計画書をクリーンアップ
# 引数:
#   $1 - dry_run: "true"の場合は削除せずに表示のみ
cleanup_closed_issue_plans() {
    local dry_run="${1:-false}"
    local plans_dir="docs/plans"
    
    if [[ ! -d "$plans_dir" ]]; then
        log_info "No plans directory found: $plans_dir"
        return 0
    fi
    
    # gh CLIが利用可能かチェック
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install: https://cli.github.com/"
        return 1
    fi
    
    local count=0
    local plan_files
    plan_files=$(find "$plans_dir" -name "issue-*-plan.md" -type f 2>/dev/null || true)
    
    if [[ -z "$plan_files" ]]; then
        log_info "No plan files found in $plans_dir"
        return 0
    fi
    
    while IFS= read -r plan_file; do
        [[ -z "$plan_file" ]] && continue
        
        # ファイル名からIssue番号を抽出
        local filename
        filename=$(basename "$plan_file")
        local issue_number
        issue_number=$(echo "$filename" | sed -n 's/issue-\([0-9]*\)-plan\.md/\1/p')
        
        if [[ -z "$issue_number" ]]; then
            log_debug "Could not extract issue number from: $filename"
            continue
        fi
        
        # Issueの状態を確認
        local issue_state
        issue_state=$(gh issue view "$issue_number" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$issue_state" == "CLOSED" ]]; then
            count=$((count + 1))
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY-RUN] Would delete: $plan_file (Issue #$issue_number is closed)"
            else
                log_info "Deleting: $plan_file (Issue #$issue_number is closed)"
                rm -f "$plan_file"
            fi
        else
            log_debug "Keeping: $plan_file (Issue #$issue_number state: $issue_state)"
        fi
    done <<< "$plan_files"
    
    if [[ $count -eq 0 ]]; then
        log_info "No closed issue plans found to delete."
    elif [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would delete $count plan file(s)"
    else
        log_info "Deleted $count plan file(s)"
    fi
}

# 孤立したステータスファイルをクリーンアップ
# 引数:
#   $1 - dry_run: "true"の場合は削除せずに表示のみ
#   $2 - age_days: 日数制限（オプション、指定時は古いファイルのみ対象）
cleanup_orphaned_statuses() {
    local dry_run="${1:-false}"
    local age_days="${2:-}"
    local orphans
    
    if [[ -n "$age_days" ]]; then
        orphans="$(find_stale_statuses "$age_days")"
    else
        orphans="$(find_orphaned_statuses)"
    fi
    
    if [[ -z "$orphans" ]]; then
        if [[ -n "$age_days" ]]; then
            log_info "No orphaned status files older than $age_days days found."
        else
            log_info "No orphaned status files found."
        fi
        return 0
    fi
    
    local count=0
    while IFS= read -r issue_number; do
        [[ -z "$issue_number" ]] && continue
        count=$((count + 1))
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would remove status file for Issue #$issue_number"
        else
            log_info "Removing orphaned status file for Issue #$issue_number"
            remove_status "$issue_number"
        fi
    done <<< "$orphans"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would remove $count orphaned status file(s)"
    else
        log_info "Removed $count orphaned status file(s)"
    fi
}

main() {
    local target=""
    local force=false
    local delete_branch=false
    local keep_session=false
    local keep_worktree=false
    local orphans=false
    local delete_plans=false
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
        log_info "Cleaning up closed issue plans..."
        cleanup_closed_issue_plans "$dry_run"
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
