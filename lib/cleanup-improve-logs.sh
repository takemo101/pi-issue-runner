#!/usr/bin/env bash
# cleanup-improve-logs.sh - .improve-logs ディレクトリのクリーンアップ関数

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CLEANUP_IMPROVE_LOGS_SH_SOURCED:-}" ]]; then
    return 0
fi
_CLEANUP_IMPROVE_LOGS_SH_SOURCED="true"

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

# 対象ログファイルを更新日時の降順で検索・一覧取得
# 引数:
#   $1 - logs_dir: 検索対象ディレクトリ
# 出力: ファイルパスを更新日時の降順で1行1ファイル出力
_find_improve_log_files() {
    local logs_dir="$1"

    local unsorted_files
    unsorted_files=$(find "$logs_dir" -name "iteration-*-*.log" -type f 2>/dev/null)

    if [[ -z "$unsorted_files" ]]; then
        return 0
    fi

    # OSを検出して適切なstatコマンドを使用
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$unsorted_files" | while IFS= read -r file; do
            local mtime
            mtime=$(stat -f '%m' "$file" 2>/dev/null)
            echo "$mtime $file"
        done | sort -rn | awk '{print $2}'
    else
        echo "$unsorted_files" | while IFS= read -r file; do
            local mtime
            mtime=$(stat -c '%Y' "$file" 2>/dev/null)
            echo "$mtime $file"
        done | sort -rn | awk '{print $2}'
    fi
}

# 個別ファイルのクリーンアップ条件を判定
# 引数:
#   $1 - log_file: 対象ファイル
#   $2 - position: ソート済みリスト中の位置（1始まり）
#   $3 - keep_recent: 保持する直近ファイル数（0=無制限）
#   $4 - keep_days: 保持する日数（0=無制限）
#   $5 - cutoff_time: カットオフ時刻（epoch秒、空文字列=日数制限なし）
# 出力: 削除理由（削除すべき場合）。保持する場合は空文字列
_should_cleanup_file() {
    local log_file="$1"
    local position="$2"
    local keep_recent="$3"
    local keep_days="$4"
    local cutoff_time="$5"

    local should_delete=false
    local reason=""

    # keep_recent の制限をチェック
    if [[ "$keep_recent" -gt 0 && "$position" -gt "$keep_recent" ]]; then
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

    if [[ "$should_delete" == "true" ]]; then
        echo "$reason"
    fi
}

# ログファイルの削除処理
# 引数:
#   $1 - log_file: 削除対象ファイル
#   $2 - reason: 削除理由
#   $3 - dry_run: "true"の場合は削除せずに表示のみ
_remove_improve_log() {
    local log_file="$1"
    local reason="$2"
    local dry_run="$3"

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would delete: $log_file ($reason)"
    else
        log_info "Deleting: $log_file ($reason)"
        rm -f "$log_file"
    fi
}

# クリーンアップ結果のサマリを出力
# 引数:
#   $1 - deleted: 削除したファイル数
#   $2 - total_count: 総ファイル数
#   $3 - keep_recent: 保持する直近ファイル数
#   $4 - keep_days: 保持する日数
#   $5 - dry_run: "true"の場合はドライランモード
_log_cleanup_summary() {
    local deleted="$1"
    local total_count="$2"
    local keep_recent="$3"
    local keep_days="$4"
    local dry_run="$5"

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

# カットオフ時刻を計算（クロスプラットフォーム対応）
# 引数:
#   $1 - keep_days: 保持する日数（0の場合は空文字列を返す）
# 出力: カットオフ時刻（epoch秒）または空文字列
_calculate_cutoff_time() {
    local keep_days="$1"

    if [[ "$keep_days" -le 0 ]]; then
        return 0
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -v-"${keep_days}d" +%s
    else
        date -d "${keep_days} days ago" +%s
    fi
}

# ログファイルリストを走査し、条件に基づいて削除を実行
# 引数:
#   $1 - log_files: 改行区切りのファイルリスト
#   $2 - keep_recent / $3 - keep_days / $4 - cutoff_time / $5 - dry_run
# 出力: 削除したファイル数を標準出力に返す
_process_improve_log_files() {
    local log_files="$1"
    local keep_recent="$2"
    local keep_days="$3"
    local cutoff_time="$4"
    local dry_run="$5"

    local deleted=0
    local line_num=0

    while IFS= read -r log_file; do
        [[ -z "$log_file" ]] && continue
        line_num=$((line_num + 1))

        local reason
        reason=$(_should_cleanup_file "$log_file" "$line_num" "$keep_recent" "$keep_days" "$cutoff_time")

        if [[ -n "$reason" ]]; then
            _remove_improve_log "$log_file" "$reason" "$dry_run"
            deleted=$((deleted + 1))
        else
            log_debug "Keeping: $log_file"
        fi
    done <<< "$log_files"

    echo "$deleted"
}

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

    local keep_recent keep_days
    keep_recent="$(get_config improve_logs_keep_recent)"
    keep_days="$(get_config improve_logs_keep_days)"
    [[ -n "$age_days" ]] && keep_days="$age_days"

    local log_files
    log_files=$(_find_improve_log_files "$logs_dir")

    if [[ -z "$log_files" ]]; then
        log_info "No improve-logs found in $logs_dir"
        return 0
    fi

    local total_count
    total_count=$(echo "$log_files" | wc -l | tr -d ' ')

    local cutoff_time
    cutoff_time=$(_calculate_cutoff_time "$keep_days")

    local deleted
    deleted=$(_process_improve_log_files "$log_files" "$keep_recent" "$keep_days" "$cutoff_time" "$dry_run")

    _log_cleanup_summary "$deleted" "$total_count" "$keep_recent" "$keep_days" "$dry_run"
}
