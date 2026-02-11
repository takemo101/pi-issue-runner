#!/usr/bin/env bash
# ============================================================================
# lib/watcher/cleanup.sh - Cleanup functions for watch-session
#
# Responsibilities:
#   - Cleanup with retry logic (_run_cleanup_with_retry)
#   - Post-cleanup maintenance (_post_cleanup_maintenance)
#   - Status and plan completion (_complete_status_and_plans)
#   - Worktree info resolution (_resolve_worktree_info)
#
# Note: These functions are used by both phase.sh and watch-session.sh
# ============================================================================

set -euo pipefail

# Source required libraries
WATCHER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../log.sh
source "$WATCHER_LIB_DIR/../log.sh"
# shellcheck source=../config.sh
source "$WATCHER_LIB_DIR/../config.sh"
# shellcheck source=../multiplexer.sh
source "$WATCHER_LIB_DIR/../multiplexer.sh"
# shellcheck source=../status.sh
source "$WATCHER_LIB_DIR/../status.sh"
# shellcheck source=../hooks.sh
source "$WATCHER_LIB_DIR/../hooks.sh"
# shellcheck source=../worktree.sh
source "$WATCHER_LIB_DIR/../worktree.sh"

# ============================================================================
# Resolve worktree information for an issue
# Usage: _resolve_worktree_info <issue_number> <worktree_path_var> <branch_name_var>
# Sets: worktree_path_var and branch_name_var via nameref
# ============================================================================
_resolve_worktree_info() {
    local issue_number="$1"
    local -n worktree_path_ref="$2"
    local -n branch_name_ref="$3"
    
    worktree_path_ref=""
    branch_name_ref=""
    
    worktree_path_ref="$(find_worktree_by_issue "$issue_number" 2>/dev/null)" || worktree_path_ref=""
    if [[ -n "$worktree_path_ref" ]]; then
        # shellcheck disable=SC2034  # Used via nameref
        branch_name_ref="$(get_worktree_branch "$worktree_path_ref" 2>/dev/null)" || branch_name_ref=""
    fi
}

# ============================================================================
# Save completion status and handle plan file deletion
# Usage: _complete_status_and_plans <issue_number> <session_name>
# ============================================================================
_complete_status_and_plans() {
    local issue_number="$1"
    local session_name="$2"
    
    # ステータスを保存
    save_status "$issue_number" "complete" "$session_name" "" 2>/dev/null || true
    
    # 計画書を削除（ホスト環境で実行するため確実に反映される）
    local plans_dir
    plans_dir="$(get_config plans_dir)"
    local plan_file="${plans_dir}/issue-${issue_number}-plan.md"
    if [[ -f "$plan_file" ]]; then
        log_info "Deleting plan file: $plan_file"
        rm -f "$plan_file"
        
        # git でコミット（失敗しても継続）
        if git rev-parse --git-dir &>/dev/null; then
            git add "$plan_file" 2>/dev/null || true
            git commit -m "chore: remove plan for issue #${issue_number}" 2>/dev/null || true
            # NOTE: Do NOT auto-push - let the PR workflow handle that
        fi
    else
        log_debug "No plan file found at: $plan_file"
    fi
}

# ============================================================================
# Run completion hooks
# Usage: _run_completion_hooks <issue_number> <session_name> <branch_name> <worktree_path> [gates_json]
# ============================================================================
_run_completion_hooks() {
    local issue_number="$1"
    local session_name="$2"
    local branch_name="$3"
    local worktree_path="$4"
    local gates_json="${5:-}"
    
    record_tracker_entry "$issue_number" "success" "" "$gates_json" 2>/dev/null || true
    
    run_hook "on_success" "$issue_number" "$session_name" "$branch_name" "$worktree_path" "" "0" "" 2>/dev/null || true
}

# ============================================================================
# Run cleanup with retry logic
# Usage: _run_cleanup_with_retry <session_name> <cleanup_args> <watcher_script_dir>
# Returns: 0 on success, 1 on failure
# ============================================================================
_run_cleanup_with_retry() {
    local session_name="$1"
    local cleanup_args="${2:-}"
    local watcher_script_dir="${3:-}"
    
    log_info "Running cleanup..."
    
    # セッション終了の最終確認（handle_complete で kill 済みだが念のため待機）
    if mux_session_exists "$session_name"; then
        local cleanup_delay
        cleanup_delay="$(get_config watcher_cleanup_delay)"
        log_info "Session still alive, waiting for termination (${cleanup_delay}s)..."
        sleep "$cleanup_delay"
    fi
    
    # cleanup実行（リトライ付き）
    local cleanup_success=false
    local cleanup_attempt=1
    local max_cleanup_attempts=2
    
    while [[ $cleanup_attempt -le $max_cleanup_attempts ]]; do
        log_info "Cleanup attempt $cleanup_attempt/$max_cleanup_attempts..."
        
        # 2回目以降は --force を追加（未コミットファイルがあっても削除）
        local force_flag=""
        if [[ $cleanup_attempt -gt 1 ]]; then
            log_info "Adding --force flag for retry attempt"
            force_flag="--force"
        fi
        
        # shellcheck disable=SC2086
        if "${watcher_script_dir}/cleanup.sh" "$session_name" $cleanup_args $force_flag; then
            cleanup_success=true
            break
        else
            log_warn "Cleanup attempt $cleanup_attempt failed"
            if [[ $cleanup_attempt -lt $max_cleanup_attempts ]]; then
                local cleanup_retry_interval
                cleanup_retry_interval="$(get_config watcher_cleanup_retry_interval)"
                log_info "Retrying in ${cleanup_retry_interval} seconds..."
                sleep "$cleanup_retry_interval"
            fi
        fi
        cleanup_attempt=$((cleanup_attempt + 1))
    done
    
    if [[ "$cleanup_success" == "false" ]]; then
        log_error "Cleanup failed after $max_cleanup_attempts attempts"
        
        # orphaned worktreeとしてマーク
        log_warn "This worktree may need manual cleanup. You can run:"
        log_warn "  ./scripts/cleanup.sh --orphan-worktrees --force"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Post-cleanup maintenance: orphan detection and plan rotation
# Usage: _post_cleanup_maintenance <watcher_script_dir>
# ============================================================================
_post_cleanup_maintenance() {
    local watcher_script_dir="${1:-}"
    
    # orphaned worktreeの検出と修復
    log_info "Checking for any orphaned worktrees with 'complete' status..."
    local orphaned_count
    orphaned_count=$(count_complete_with_existing_worktrees)
    
    if [[ "$orphaned_count" -gt 0 ]]; then
        log_info "Found $orphaned_count orphaned worktree(s) with 'complete' status. Cleaning up..."
        # shellcheck source=../cleanup-orphans.sh
        cleanup_complete_with_worktrees "false" "false" || {
            log_warn "Some orphaned worktrees could not be cleaned up automatically"
        }
    else
        log_debug "No orphaned worktrees found"
    fi
    
    # 古い計画書をローテーション
    log_info "Rotating old plans..."
    "${watcher_script_dir}/cleanup.sh" --rotate-plans 2>/dev/null || {
        log_warn "Plan rotation failed (non-critical)"
    }
}

# Export functions for use by watch-session.sh
export -f _resolve_worktree_info
export -f _complete_status_and_plans
export -f _run_completion_hooks
export -f _run_cleanup_with_retry
export -f _post_cleanup_maintenance
