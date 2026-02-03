#!/usr/bin/env bash
# cleanup-improve-logs.sh - .improve-logs ディレクトリのクリーンアップ関数

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

# 自身のディレクトリを取得
_CLEANUP_IMPROVE_LOGS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config.shがまだロードされていなければロード
if ! declare -f get_config > /dev/null 2>&1; then
    source "$_CLEANUP_IMPROVE_LOGS_LIB_DIR/config.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# improve-logsディレクトリをクリーンアップ（直近N件を保持、N日以内を保持）
# 引数:
#   $1 - dry_run: "true"の場合は削除せずに表示のみ
#   $2 - age_days: 日数制限（オプション、指定時は設定を上書き）
cleanup_improve_logs() {
    local dry_run="${1:-false}"
    local age_days="${2:-}"
    
    load_config
    
    local logs_dir
    logs_dir="$(get_config improve_logs_dir)"
    
    if [[ ! -d "$logs_dir" ]]; then
        log_debug "No improve-logs directory found: $logs_dir"
        return 0
    fi
    
    local keep_recent
    keep_recent="$(get_config improve_logs_keep_recent)"
    
    local keep_days
    keep_days="$(get_config improve_logs_keep_days)"
    
    # age_days パラメータが指定された場合は設定を上書き
    if [[ -n "$age_days" ]]; then
        keep_days="$age_days"
    fi
    
    # ログファイルを更新日時の降順でソート
    local log_files=""
    local unsorted_files
    unsorted_files=$(find "$logs_dir" -name "iteration-*-*.log" -type f 2>/dev/null)
    
    if [[ -z "$unsorted_files" ]]; then
        log_info "No improve-logs found in $logs_dir"
        return 0
    fi
    
    # OSを検出して適切なstatコマンドを使用
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS/BSD: stat -f '%m %N' (modification time in seconds, filename)
        log_files=$(echo "$unsorted_files" | while IFS= read -r file; do
            local mtime
            mtime=$(stat -f '%m' "$file" 2>/dev/null)
            echo "$mtime $file"
        done | sort -rn | awk '{print $2}')
    else
        # Linux/GNU: stat -c '%Y %n' (modification time in seconds, filename)
        log_files=$(echo "$unsorted_files" | while IFS= read -r file; do
            local mtime
            mtime=$(stat -c '%Y' "$file" 2>/dev/null)
            echo "$mtime $file"
        done | sort -rn | awk '{print $2}')
    fi
    
    local total_count
    total_count=$(echo "$log_files" | wc -l | tr -d ' ')
    
    local deleted=0
    local line_num=0
    local cutoff_time=""
    
    # keep_days が設定されている場合はカットオフ時刻を計算
    if [[ "$keep_days" -gt 0 ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS/BSD: date -v
            cutoff_time=$(date -v-"${keep_days}d" +%s)
        else
            # Linux/GNU: date -d
            cutoff_time=$(date -d "${keep_days} days ago" +%s)
        fi
    fi
    
    # 各ログファイルを処理
    while IFS= read -r log_file; do
        [[ -z "$log_file" ]] && continue
        line_num=$((line_num + 1))
        
        local should_delete=false
        local reason=""
        
        # keep_recent の制限をチェック
        if [[ "$keep_recent" -gt 0 && "$line_num" -gt "$keep_recent" ]]; then
            should_delete=true
            reason="exceeds keep_recent limit ($keep_recent)"
        fi
        
        # keep_days の制限をチェック
        if [[ "$keep_days" -gt 0 && -n "$cutoff_time" ]]; then
            local file_mtime
            if [[ "$OSTYPE" == "darwin"* ]]; then
                file_mtime=$(stat -f '%m' "$log_file" 2>/dev/null)
            else
                file_mtime=$(stat -c '%Y' "$log_file" 2>/dev/null)
            fi
            
            if [[ "$file_mtime" -lt "$cutoff_time" ]]; then
                should_delete=true
                if [[ -n "$reason" ]]; then
                    reason="$reason and older than ${keep_days} days"
                else
                    reason="older than ${keep_days} days"
                fi
            fi
        fi
        
        # 削除または保持の判定
        if [[ "$should_delete" == "true" ]]; then
            deleted=$((deleted + 1))
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY-RUN] Would delete: $log_file ($reason)"
            else
                log_info "Deleting: $log_file ($reason)"
                rm -f "$log_file"
            fi
        else
            log_debug "Keeping: $log_file"
        fi
    done <<< "$log_files"
    
    # サマリ
    if [[ $deleted -eq 0 ]]; then
        if [[ "$keep_recent" -eq 0 && "$keep_days" -eq 0 ]]; then
            log_info "Cleanup disabled (keep_recent=0, keep_days=0)"
        else
            log_info "No improve-logs to delete (total: $total_count)"
        fi
    elif [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would delete $deleted log file(s), keeping $((total_count - deleted))"
    else
        log_info "Deleted $deleted log file(s), kept $((total_count - deleted))"
    fi
}
