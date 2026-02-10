#!/usr/bin/env bash
# ============================================================================
# tracker.sh - プロンプト効果測定（タスク成功/失敗の記録）
#
# ワークフロー別の成功率をJSONL形式で記録する。
# watch-session.sh の handle_complete / handle_error から呼び出される。
#
# Provides:
#   - record_tracker_entry: タスク結果をJSONLファイルに記録
#   - get_tracker_file: トラッカーファイルパスを取得
#   - save_tracker_metadata: ワークフロー名・開始時刻をメタデータとして保存
#   - load_tracker_metadata: メタデータを読み込み
#   - remove_tracker_metadata: メタデータファイルを削除
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_TRACKER_SH_SOURCED:-}" ]]; then
    return 0
fi
_TRACKER_SH_SOURCED="true"

_TRACKER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリの読み込み（未読み込みの場合のみ）
if ! declare -f get_config &>/dev/null; then
    source "$_TRACKER_LIB_DIR/config.sh"
fi

if ! declare -f log_info &>/dev/null; then
    source "$_TRACKER_LIB_DIR/log.sh"
fi

if ! declare -f get_status_dir &>/dev/null; then
    source "$_TRACKER_LIB_DIR/status.sh"
fi

# ===================
# トラッカーファイル管理
# ===================

# トラッカーファイルのパスを取得
# Usage: get_tracker_file
# Output: トラッカーファイルのフルパス
get_tracker_file() {
    load_config 2>/dev/null || true

    local tracker_file
    tracker_file="$(get_config tracker_file)"

    if [[ -z "$tracker_file" ]]; then
        local status_dir
        status_dir="$(get_status_dir)"
        tracker_file="${status_dir}/tracker.jsonl"
    fi

    echo "$tracker_file"
}

# ===================
# メタデータ管理
# ===================

# セッション開始時にワークフロー名と開始時刻を保存
# Usage: save_tracker_metadata <issue_number> <workflow_name>
save_tracker_metadata() {
    local issue_number="$1"
    local workflow_name="$2"

    local status_dir
    status_dir="$(get_status_dir)"
    mkdir -p "$status_dir"

    local meta_file="${status_dir}/${issue_number}.tracker-meta"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local epoch
    epoch="$(date +%s)"

    # Atomic write
    local tmp_file="${meta_file}.tmp.$$"
    printf '%s\n%s\n%s\n' "$workflow_name" "$timestamp" "$epoch" > "$tmp_file"
    mv -f "$tmp_file" "$meta_file"

    log_debug "Saved tracker metadata for issue #$issue_number: workflow=$workflow_name"
}

# メタデータを読み込み
# Usage: load_tracker_metadata <issue_number>
# Output: "workflow_name<TAB>start_timestamp<TAB>start_epoch" (1行)
# Returns: 0=success, 1=not found
load_tracker_metadata() {
    local issue_number="$1"

    local status_dir
    status_dir="$(get_status_dir)"
    local meta_file="${status_dir}/${issue_number}.tracker-meta"

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    local workflow_name start_timestamp start_epoch
    {
        IFS= read -r workflow_name
        IFS= read -r start_timestamp
        IFS= read -r start_epoch
    } < "$meta_file"

    printf '%s\t%s\t%s\n' "$workflow_name" "$start_timestamp" "$start_epoch"
}

# メタデータファイルを削除
# Usage: remove_tracker_metadata <issue_number>
remove_tracker_metadata() {
    local issue_number="$1"

    local status_dir
    status_dir="$(get_status_dir)"
    local meta_file="${status_dir}/${issue_number}.tracker-meta"

    rm -f "$meta_file"
}

# ===================
# 記録
# ===================

# タスク結果をJSONL形式で記録
# Usage: record_tracker_entry <issue_number> <result> [error_type] [gates_json]
# Arguments:
#   issue_number - Issue番号
#   result       - "success", "error", or "abandoned"
#   error_type   - エラー分類（任意、result=error時のみ）
#   gates_json   - ゲート結果JSON（任意、GATE_RESULTS_JSON から取得可能）
record_tracker_entry() {
    local issue_number="$1"
    local result="$2"
    local error_type="${3:-}"
    local gates_json="${4:-}"

    local tracker_file
    tracker_file="$(get_tracker_file)"

    local tracker_dir
    tracker_dir="$(dirname "$tracker_file")"
    mkdir -p "$tracker_dir"

    local workflow_name="unknown"
    local start_epoch=""
    local meta_line=""
    if meta_line="$(load_tracker_metadata "$issue_number" 2>/dev/null)"; then
        workflow_name="$(printf '%s' "$meta_line" | cut -f1)"
        start_epoch="$(printf '%s' "$meta_line" | cut -f3)"
    fi

    local duration_sec=0
    local now_epoch
    now_epoch="$(date +%s)"
    if [[ -n "$start_epoch" && "$start_epoch" =~ ^[0-9]+$ ]]; then
        duration_sec=$((now_epoch - start_epoch))
    fi

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local json_entry
    if command -v jq &>/dev/null; then
        local jq_args=(
            -c -n
            --argjson issue "$issue_number"
            --arg workflow "$workflow_name"
            --arg result "$result"
            --argjson duration_sec "$duration_sec"
            --arg timestamp "$timestamp"
        )
        local jq_expr='{issue: $issue, workflow: $workflow, result: $result, duration_sec: $duration_sec, timestamp: $timestamp}'

        if [[ -n "$error_type" ]]; then
            jq_args+=(--arg error_type "$error_type")
            jq_expr='{issue: $issue, workflow: $workflow, result: $result, duration_sec: $duration_sec, error_type: $error_type, timestamp: $timestamp}'
        fi

        json_entry="$(jq "${jq_args[@]}" "$jq_expr")"

        if [[ -n "$gates_json" ]]; then
            local gates_obj total_retries
            gates_obj="$(printf '%s' "$gates_json" | jq -c '.gates // {}' 2>/dev/null)" || gates_obj="{}"
            total_retries="$(printf '%s' "$gates_json" | jq '.total_gate_retries // 0' 2>/dev/null)" || total_retries="0"
            json_entry="$(printf '%s' "$json_entry" | jq -c \
                --argjson gates "$gates_obj" \
                --argjson total_gate_retries "$total_retries" \
                '. + {gates: $gates, total_gate_retries: $total_gate_retries}')"
        fi
    else
        local base_json
        if [[ -n "$error_type" ]]; then
            base_json="\"issue\":${issue_number},\"workflow\":\"${workflow_name}\",\"result\":\"${result}\",\"duration_sec\":${duration_sec},\"error_type\":\"${error_type}\",\"timestamp\":\"${timestamp}\""
        else
            base_json="\"issue\":${issue_number},\"workflow\":\"${workflow_name}\",\"result\":\"${result}\",\"duration_sec\":${duration_sec},\"timestamp\":\"${timestamp}\""
        fi

        if [[ -n "$gates_json" ]]; then
            local gates_part total_retries_part
            gates_part="$(printf '%s' "$gates_json" | grep -o '"gates":{[^}]*}' | head -1)" || gates_part=""
            total_retries_part="$(printf '%s' "$gates_json" | grep -o '"total_gate_retries":[0-9]*' | head -1)" || total_retries_part=""
            if [[ -n "$gates_part" && -n "$total_retries_part" ]]; then
                json_entry="{${base_json},${gates_part},${total_retries_part}}"
            else
                json_entry="{${base_json}}"
            fi
        else
            json_entry="{${base_json}}"
        fi
    fi

    printf '%s\n' "$json_entry" >> "$tracker_file"
    log_info "Tracker: recorded ${result} for issue #${issue_number} (workflow: ${workflow_name}, duration: ${duration_sec}s)"

    remove_tracker_metadata "$issue_number"
}
