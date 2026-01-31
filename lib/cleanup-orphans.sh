#!/usr/bin/env bash
# cleanup-orphans.sh - 孤立したステータスファイルのクリーンアップ関数

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

# 自身のディレクトリを取得
_CLEANUP_ORPHANS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# status.shがまだロードされていなければロード
if ! declare -f find_orphaned_statuses > /dev/null 2>&1; then
    source "$_CLEANUP_ORPHANS_LIB_DIR/status.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

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
