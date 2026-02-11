#!/usr/bin/env bash
# ============================================================================
# run/worktree.sh - Worktree and session management for run.sh
#
# Handles worktree creation, existing session checks, and setup operations.
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_RUN_WORKTREE_SH_SOURCED:-}" ]]; then
    return 0
fi
_RUN_WORKTREE_SH_SOURCED="true"

# ライブラリディレクトリを取得
_RUN_WORKTREE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存関係の読み込み
source "$_RUN_WORKTREE_LIB_DIR/../config.sh"
source "$_RUN_WORKTREE_LIB_DIR/../log.sh"
source "$_RUN_WORKTREE_LIB_DIR/../worktree.sh"
source "$_RUN_WORKTREE_LIB_DIR/../multiplexer.sh"
source "$_RUN_WORKTREE_LIB_DIR/../cleanup-trap.sh"
source "$_RUN_WORKTREE_LIB_DIR/../github.sh"

# ============================================================================
# Handle existing session check and management
# Arguments: $1=issue_number, $2=reattach, $3=force
# Output: Sets global variable _SESSION_name
# ============================================================================
handle_existing_session() {
    local issue_number="$1"
    local reattach="$2"
    local force="$3"

    local session_name
    session_name="$(mux_generate_session_name "$issue_number")"

    if mux_session_exists "$session_name"; then
        if [[ "$reattach" == "true" ]]; then
            log_info "Attaching to existing session: $session_name"
            mux_attach_session "$session_name"
            exit 0
        elif [[ "$force" == "true" ]]; then
            log_info "Removing existing session: $session_name"
            mux_kill_session "$session_name" || true
        else
            log_error "Session '$session_name' already exists."
            log_info "Options:"
            log_info "  --reattach  Attach to existing session"
            log_info "  --force     Remove and recreate session"
            exit 1
        fi
    fi

    # 並列実行数の制限チェック（--forceの場合はスキップ）
    if [[ "$force" != "true" ]]; then
        if ! mux_check_concurrent_limit; then
            exit 1
        fi
    fi

    # Set global variable (no escaping needed)
    _SESSION_name="$session_name"
}

# ============================================================================
# Setup worktree for the issue
# Arguments: $1=issue_number, $2=custom_branch, $3=base_branch, $4=force
# Output: Sets global variables with _WORKTREE_ prefix
# ============================================================================
setup_worktree() {
    local issue_number="$1"
    local custom_branch="$2"
    local base_branch="$3"
    local force="$4"

    # ブランチ名決定
    local branch_name
    if [[ -n "$custom_branch" ]]; then
        branch_name="$custom_branch"
    else
        branch_name="$(issue_to_branch_name "$issue_number")"
    fi
    log_info "Branch: feature/$branch_name"

    # 既存Worktreeのチェック
    local existing_worktree
    if existing_worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
        if [[ "$force" == "true" ]]; then
            log_info "Removing existing worktree: $existing_worktree"
            remove_worktree "$existing_worktree" true || true
        else
            log_error "Worktree already exists: $existing_worktree"
            log_info "Options:"
            log_info "  --force     Remove and recreate worktree"
            exit 1
        fi
    fi

    # Worktree作成
    log_info "=== Creating Worktree ==="
    local worktree_path
    worktree_path="$(create_worktree "$branch_name" "$base_branch")"
    local full_worktree_path
    full_worktree_path="$(cd "$worktree_path" && pwd)"
    
    # エラー時クリーンアップ用にworktreeを登録
    register_worktree_for_cleanup "$full_worktree_path"

    # Set global variables (no escaping needed)
    _WORKTREE_branch_name="$branch_name"
    _WORKTREE_path="$worktree_path"
    _WORKTREE_full_path="$full_worktree_path"
}
