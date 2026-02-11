#!/usr/bin/env bash
# status.sh - ステータスファイル管理

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_STATUS_SH_SOURCED:-}" ]]; then
    return 0
fi
_STATUS_SH_SOURCED="true"

# 自身のディレクトリを取得（SCRIPT_DIRとは別に保存）
_STATUS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config.shがまだロードされていなければロード
if ! declare -f get_config > /dev/null 2>&1; then
    source "$_STATUS_LIB_DIR/config.sh"
fi

# ログ関数（log.shがロードされていなければダミー）
if ! declare -f log_debug > /dev/null 2>&1; then
    log_debug() { :; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# JSONエスケープ関数
# 引数:
#   $1 - 文字列
# 出力: JSONエスケープされた文字列
json_escape() {
    local str="$1"
    # バックスラッシュを最初にエスケープ（順序重要）
    str="${str//\\/\\\\}"
    # ダブルクォート
    str="${str//\"/\\\"}"
    # タブ
    str="${str//$'\t'/\\t}"
    # 改行
    str="${str//$'\n'/\\n}"
    # キャリッジリターン
    str="${str//$'\r'/\\r}"
    # バックスペース
    str="${str//$'\b'/\\b}"
    # フォームフィード
    str="${str//$'\f'/\\f}"
    echo "$str"
}

# ステータスJSONを構築（統一関数）
# jqがあれば使用、なければbuild_json_fallbackにフォールバック
# 引数:
#   $1 - issue_number
#   $2 - status
#   $3 - session_name
#   $4 - timestamp
#   $5 - error_message (オプション)
#   $6 - session_label (オプション)
# 出力: JSON文字列
build_status_json() {
    local issue_number="$1"
    local status="$2"
    local session_name="$3"
    local timestamp="$4"
    local error_message="${5:-}"
    local session_label="${6:-}"

    if command -v jq &>/dev/null; then
        jq -n \
            --argjson issue "$issue_number" \
            --arg status "$status" \
            --arg session "$session_name" \
            --arg timestamp "$timestamp" \
            --arg error "$error_message" \
            --arg label "$session_label" \
            '{issue: $issue, status: $status, session: $session, timestamp: $timestamp}
             | if $error != "" then . + {error_message: $error} else . end
             | if $label != "" then . + {session_label: $label} else . end'
    else
        build_json_fallback "$@"
    fi
}

# 後方互換エイリアス: build_json_with_jq → build_status_json
# 引数:
#   $1 - issue_number
#   $2 - status
#   $3 - session_name
#   $4 - timestamp
#   $5 - error_message (オプション)
#   $6 - session_label (オプション)
# 出力: JSON文字列
build_json_with_jq() {
    build_status_json "$@"
}

# jqなしでJSONを構築（フォールバック）
# 引数:
#   $1 - issue_number
#   $2 - status
#   $3 - session_name
#   $4 - timestamp
#   $5 - error_message (オプション)
#   $6 - session_label (オプション)
# 出力: JSON文字列
build_json_fallback() {
    local issue_number="$1"
    local status="$2"
    local session_name="$3"
    local timestamp="$4"
    local error_message="${5:-}"
    local session_label="${6:-}"
    
    local escaped_status escaped_session escaped_timestamp
    escaped_status="$(json_escape "$status")"
    escaped_session="$(json_escape "$session_name")"
    escaped_timestamp="$(json_escape "$timestamp")"
    
    local json_base="{
  \"issue\": $issue_number,
  \"status\": \"$escaped_status\",
  \"session\": \"$escaped_session\""
    
    if [[ -n "$error_message" ]]; then
        local escaped_message
        escaped_message="$(json_escape "$error_message")"
        json_base="$json_base,
  \"error_message\": \"$escaped_message\""
    fi
    
    if [[ -n "$session_label" ]]; then
        local escaped_label
        escaped_label="$(json_escape "$session_label")"
        json_base="$json_base,
  \"session_label\": \"$escaped_label\""
    fi
    
    json_base="$json_base,
  \"timestamp\": \"$escaped_timestamp\"
}"
    
    echo "$json_base"
}

# ステータスディレクトリを取得
get_status_dir() {
    load_config
    local worktree_base
    worktree_base="$(get_config worktree_base_dir)"
    echo "${worktree_base}/.status"
}

# ステータスディレクトリを初期化
init_status_dir() {
    local status_dir
    status_dir="$(get_status_dir)"
    if [[ ! -d "$status_dir" ]]; then
        mkdir -p "$status_dir"
        log_debug "Created status directory: $status_dir"
    fi
}

# ステータスを保存
# 引数:
#   $1 - issue_number: Issue番号
#   $2 - status: ステータス (running, error, complete)
#   $3 - session_name: セッション名
#   $4 - error_message: エラーメッセージ (オプション)
#   $5 - session_label: セッションラベル (オプション、improve.shで使用)
save_status() {
    local issue_number="$1"
    local status="$2"
    local session_name="${3:-}"
    local error_message="${4:-}"
    local session_label="${5:-}"
    
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local status_file="${status_dir}/${issue_number}.json"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    # JSONを構築（統一関数: jqがあれば使用、なければフォールバック）
    local json
    json="$(build_status_json "$issue_number" "$status" "$session_name" "$timestamp" "$error_message" "$session_label")"
    
    # Atomic write: write to temp file and rename
    local tmp_file="${status_file}.tmp.$$"
    echo "$json" > "$tmp_file"
    mv -f "$tmp_file" "$status_file"
    log_debug "Saved status for issue #$issue_number: $status (label: ${session_label:-none})"
}

# ステータスを設定（Issue仕様に合わせたエイリアス）
# 引数:
#   $1 - issue: Issue番号
#   $2 - status: ステータス (running, error, complete)
#   $3 - message: メッセージ (オプション、エラー時のみ使用)
set_status() {
    local issue="$1"
    local status="$2"
    local message="${3:-}"
    
    # セッション名を生成
    local session_name
    if declare -f generate_session_name > /dev/null 2>&1; then
        session_name="$(generate_session_name "$issue")"
    else
        session_name="pi-issue-${issue}"
    fi
    
    if [[ "$status" == "error" ]]; then
        save_status "$issue" "$status" "$session_name" "$message"
    else
        save_status "$issue" "$status" "$session_name"
    fi
}

# ステータスを読み込み
# 引数:
#   $1 - issue_number: Issue番号
# 出力: JSONの内容、またはファイルがなければ空
load_status() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local status_file="${status_dir}/${issue_number}.json"
    
    if [[ -f "$status_file" ]]; then
        cat "$status_file"
    fi
}

# ステータス値のみを取得
# 引数:
#   $1 - issue_number: Issue番号
# 出力: ステータス文字列 (running, error, complete) または "unknown"
get_status_value() {
    local issue_number="$1"
    
    local json
    json="$(load_status "$issue_number")"
    
    if [[ -n "$json" ]]; then
        # jqを使用してstatusフィールドを抽出（null時は"unknown"を返す）
        if command -v jq &>/dev/null; then
            echo "$json" | jq -r '.status // "unknown"'
        else
            # jqがない場合はフォールバック（grep/sed）
            echo "$json" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# ステータスを取得（Issue仕様に合わせたエイリアス）
# 引数:
#   $1 - issue: Issue番号
# 出力: ステータス文字列 (running, error, complete) または "unknown"
get_status() {
    get_status_value "$1"
}

# エラーメッセージを取得
# 引数:
#   $1 - issue_number: Issue番号
# 出力: エラーメッセージまたは空
get_error_message() {
    local issue_number="$1"
    
    local json
    json="$(load_status "$issue_number")"
    
    if [[ -n "$json" ]]; then
        # jqを使用してerror_messageフィールドを抽出（null時は空文字列を返す）
        if command -v jq &>/dev/null; then
            echo "$json" | jq -r '.error_message // ""'
        else
            # jqがない場合はフォールバック（grep/sed）
            echo "$json" | grep -o '"error_message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || true
        fi
    fi
}

# ステータスファイルを削除
# 引数:
#   $1 - issue_number: Issue番号
remove_status() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local status_file="${status_dir}/${issue_number}.json"
    
    if [[ -f "$status_file" ]]; then
        rm -f "$status_file"
        log_debug "Removed status file for issue #$issue_number"
    fi
}

# 全てのステータスを一覧取得
# 出力: Issue番号とステータスのペア（タブ区切り）
list_all_statuses() {
    local status_dir
    status_dir="$(get_status_dir)"
    
    if [[ ! -d "$status_dir" ]]; then
        return 0
    fi
    
    for status_file in "$status_dir"/*.json; do
        [[ -f "$status_file" ]] || continue
        local issue_number
        issue_number="$(basename "$status_file" .json)"
        local status
        status="$(get_status_value "$issue_number")"
        echo -e "${issue_number}\t${status}"
    done
}

# セッションラベルを取得
# 引数:
#   $1 - issue_number: Issue番号
# 出力: セッションラベル文字列または空
get_session_label() {
    local issue_number="$1"
    
    local json
    json="$(load_status "$issue_number")"
    
    if [[ -n "$json" ]]; then
        # jqを使用してsession_labelフィールドを抽出（null時は空文字列を返す）
        if command -v jq &>/dev/null; then
            echo "$json" | jq -r '.session_label // ""'
        else
            # jqがない場合はフォールバック（grep/sed）
            echo "$json" | grep -o '"session_label"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || true
        fi
    fi
}

# 指定ステータスのIssue一覧を取得
# 引数:
#   $1 - status: フィルタするステータス
# 出力: Issue番号（1行に1つ）
list_issues_by_status() {
    local filter_status="$1"
    
    list_all_statuses | while IFS=$'\t' read -r issue status; do
        if [[ "$status" == "$filter_status" ]]; then
            echo "$issue"
        fi
    done
}

# 指定ステータスとラベルのIssue一覧を取得
# 引数:
#   $1 - status: フィルタするステータス
#   $2 - label: フィルタするラベル（空の場合はラベルなしのみ）
# 出力: Issue番号（1行に1つ）
list_issues_by_status_and_label() {
    local filter_status="$1"
    local filter_label="${2:-}"
    
    list_issues_by_status "$filter_status" | while IFS= read -r issue; do
        local label
        label="$(get_session_label "$issue")"
        
        # ラベルが一致する場合のみ出力
        if [[ "$label" == "$filter_label" ]]; then
            echo "$issue"
        fi
    done
}

# 孤立したステータスファイルを検出
# （対応するworktreeが存在しないステータスファイル）
# 出力: 孤立したIssue番号（1行に1つ）
find_orphaned_statuses() {
    local status_dir
    status_dir="$(get_status_dir)"
    
    if [[ ! -d "$status_dir" ]]; then
        return 0
    fi
    
    load_config
    local worktree_base
    worktree_base="$(get_config worktree_base_dir)"
    
    for status_file in "$status_dir"/*.json; do
        [[ -f "$status_file" ]] || continue
        local issue_number
        issue_number="$(basename "$status_file" .json)"
        
        # 対応するworktreeが存在するか確認
        # find_worktree_by_issue() と同じパターンで検索
        # issue-42 と issue-42-fix-bug の両方にマッチし、issue-421 には誤マッチしない
        local has_worktree=false
        for dir in "$worktree_base"/issue-"${issue_number}"-* "$worktree_base"/issue-"${issue_number}"; do
            if [[ -d "$dir" ]]; then
                has_worktree=true
                break
            fi
        done
        
        # worktreeが存在しない場合は孤立
        if [[ "$has_worktree" == "false" ]]; then
            echo "$issue_number"
        fi
    done
}

# 指定日数より古いステータスファイルを検出
# 引数:
#   $1 - days: 日数（この日数より古いファイルを検出）
# 出力: 古いIssue番号（1行に1つ）
find_old_statuses() {
    local days="${1:-7}"
    local status_dir
    status_dir="$(get_status_dir)"
    
    if [[ ! -d "$status_dir" ]]; then
        return 0
    fi
    
    # findを使って指定日数より古いファイルを検索
    while IFS= read -r status_file; do
        [[ -z "$status_file" ]] && continue
        local issue_number
        issue_number="$(basename "$status_file" .json)"
        echo "$issue_number"
    done < <(find "$status_dir" -name "*.json" -type f -mtime +"$days" 2>/dev/null || true)
}

# 孤立かつ古いステータスファイルを検出
# 引数:
#   $1 - days: 日数（オプション、指定時は日数制限を追加）
# 出力: Issue番号（1行に1つ）
find_stale_statuses() {
    local days="${1:-}"
    
    if [[ -n "$days" ]]; then
        # 孤立 AND 指定日数より古いファイル
        local orphans old_statuses
        orphans=$(find_orphaned_statuses | sort)
        old_statuses=$(find_old_statuses "$days" | sort)
        # 両方に含まれるものを抽出
        comm -12 <(echo "$orphans") <(echo "$old_statuses")
    else
        # 孤立ファイルのみ
        find_orphaned_statuses
    fi
}

# 孤立したステータスファイルの数を取得
# 出力: 孤立ファイル数
count_orphaned_statuses() {
    local count=0
    while IFS= read -r _; do
        count=$((count + 1))
    done < <(find_orphaned_statuses)
    echo "$count"
}

# =============================================================================
# Backward compatibility: source extracted modules
# Watcher PID functions moved to lib/watcher-pid.sh (Issue #1430)
# Cleanup lock functions moved to lib/lock.sh (Issue #1430)
# =============================================================================
source "$_STATUS_LIB_DIR/watcher-pid.sh"
source "$_STATUS_LIB_DIR/lock.sh"
