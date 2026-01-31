#!/usr/bin/env bash
# status.sh - ステータスファイル管理

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

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
save_status() {
    local issue_number="$1"
    local status="$2"
    local session_name="${3:-}"
    local error_message="${4:-}"
    
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local status_file="${status_dir}/${issue_number}.json"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    # JSONを手動で構築（jqがない環境でも動作するように）
    local json
    if [[ -n "$error_message" ]]; then
        # エラーメッセージをJSONエスケープ
        local escaped_message
        escaped_message="$(echo "$error_message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' ')"
        json=$(cat << EOF
{
  "issue": $issue_number,
  "status": "$status",
  "session": "$session_name",
  "error_message": "$escaped_message",
  "timestamp": "$timestamp"
}
EOF
)
    else
        json=$(cat << EOF
{
  "issue": $issue_number,
  "status": "$status",
  "session": "$session_name",
  "timestamp": "$timestamp"
}
EOF
)
    fi
    
    echo "$json" > "$status_file"
    log_debug "Saved status for issue #$issue_number: $status"
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
        # "status": "value" からvalueを抽出
        echo "$json" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || echo "unknown"
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
        # "error_message": "value" からvalueを抽出
        echo "$json" | grep -o '"error_message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || true
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
