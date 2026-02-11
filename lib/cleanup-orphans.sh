#!/usr/bin/env bash
# cleanup-orphans.sh - 孤立したステータスファイルのクリーンアップ関数

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CLEANUP_ORPHANS_SH_SOURCED:-}" ]]; then
    return 0
fi
_CLEANUP_ORPHANS_SH_SOURCED="true"

# 自身のディレクトリを取得
_CLEANUP_ORPHANS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# status.shがまだロードされていなければロード
if ! declare -f find_orphaned_statuses > /dev/null 2>&1; then
    source "$_CLEANUP_ORPHANS_LIB_DIR/status.sh"
fi

# worktree.shがまだロードされていなければロード
if ! declare -f find_worktree_by_issue > /dev/null 2>&1; then
    source "$_CLEANUP_ORPHANS_LIB_DIR/worktree.sh"
fi

# multiplexer.shがまだロードされていなければロード（mux_session_exists関数用）
if ! declare -f mux_session_exists > /dev/null 2>&1; then
    source "$_CLEANUP_ORPHANS_LIB_DIR/multiplexer.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# Issue番号からセッション名を取得
# 引数:
#   $1 - issue_number: Issue番号
# 出力: セッション名（存在しない場合は空）
get_session_name_for_issue() {
    local issue_number="$1"
    local status_file
    status_file="$(get_status_dir)/${issue_number}.json"

    if [[ -f "$status_file" ]]; then
        # jqがあれば使用、なければgrep/sedで抽出
        if command -v jq &>/dev/null; then
            jq -r '.session // empty' "$status_file"
        else
            # フォールバック: grep/sedで抽出
            grep -o '"session"[[:space:]]*:[[:space:]]*"[^"]*"' "$status_file" 2>/dev/null | sed 's/.*"session"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true
        fi
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

# complete状態だがworktreeが残存しているケースを検出
# 出力: "<issue_number>\t<worktree_path>" の形式（1行に1つ）
find_complete_with_existing_worktrees() {
    local status_dir
    status_dir="$(get_status_dir)"
    
    if [[ ! -d "$status_dir" ]]; then
        return 0
    fi
    
    for status_file in "$status_dir"/*.json; do
        [[ -f "$status_file" ]] || continue
        local issue_number
        issue_number="$(basename "$status_file" .json)"
        
        # complete状態か確認
        local status
        status="$(get_status_value "$issue_number")"
        [[ "$status" == "complete" ]] || continue

        # ★追加: セッションが存在する場合はスキップ（レースコンディション対策）
        # Issue #549: 並列実行時に他のセッションのworktreeが誤削除される問題を防止
        local session_name
        session_name="$(get_session_name_for_issue "$issue_number")"
        if [[ -n "$session_name" ]] && mux_session_exists "$session_name"; then
            log_debug "Skipping Issue #$issue_number - session still active: $session_name"
            continue
        fi

        # 対応するworktreeが存在するか確認
        local worktree
        if worktree="$(find_worktree_by_issue "$issue_number" 2>/dev/null)"; then
            echo -e "${issue_number}\t${worktree}"
        fi
    done
}

# complete状態だがworktreeが残存しているケースの数を取得
count_complete_with_existing_worktrees() {
    local count=0
    while IFS= read -r _; do
        count=$((count + 1))
    done < <(find_complete_with_existing_worktrees)
    echo "$count"
}

# complete状態だがworktreeが残存しているケースをクリーンアップ
# 引数:
#   $1 - dry_run: "true"の場合は削除せずに表示のみ
#   $2 - force: "true"の場合はforceオプションを使用
cleanup_complete_with_worktrees() {
    local dry_run="${1:-false}"
    local force="${2:-false}"
    local entries
    
    entries="$(find_complete_with_existing_worktrees)"
    
    if [[ -z "$entries" ]]; then
        log_info "No orphaned worktrees with 'complete' status found."
        return 0
    fi
    
    local count=0
    while IFS=$'\t' read -r issue_number worktree; do
        [[ -z "$issue_number" ]] && continue
        count=$((count + 1))
        
        local branch_name=""
        branch_name="$(get_worktree_branch "$worktree" 2>/dev/null)" || branch_name=""
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would cleanup Issue #$issue_number"
            log_info "[DRY-RUN]   Worktree: $worktree"
            [[ -n "$branch_name" ]] && log_info "[DRY-RUN]   Branch: $branch_name"
        else
            log_info "Cleaning up orphaned worktree for Issue #$issue_number"
            
            # worktree削除
            if remove_worktree "$worktree" "$force"; then
                log_info "  Worktree removed: $worktree"
                
                # ステータスファイル削除
                remove_status "$issue_number"
                log_info "  Status file removed"
                
                # ブランチ削除
                if [[ -n "$branch_name" ]]; then
                    if git branch -d "$branch_name" 2>/dev/null; then
                        log_info "  Branch removed: $branch_name"
                    elif [[ "$force" == "true" ]] && git branch -D "$branch_name" 2>/dev/null; then
                        log_info "  Branch force-removed: $branch_name"
                    else
                        log_warn "  Failed to remove branch: $branch_name"
                    fi
                fi
            else
                log_error "  Failed to remove worktree: $worktree"
                log_error "  You may need to manually run cleanup with --force"
            fi
        fi
    done <<< "$entries"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would cleanup $count orphaned worktree(s) with 'complete' status"
    else
        log_info "Cleaned up $count orphaned worktree(s) with 'complete' status"
    fi
}
