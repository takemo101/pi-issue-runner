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

# jqを使用してJSONを構築
# 引数:
#   $1 - issue_number
#   $2 - status
#   $3 - session_name
#   $4 - timestamp
#   $5 - error_message (オプション)
#   $6 - session_label (オプション)
# 出力: JSON文字列
build_json_with_jq() {
    local issue_number="$1"
    local status="$2"
    local session_name="$3"
    local timestamp="$4"
    local error_message="${5:-}"
    local session_label="${6:-}"
    
    local base_args=(
        -n
        --argjson issue "$issue_number"
        --arg status "$status"
        --arg session "$session_name"
        --arg timestamp "$timestamp"
    )
    
    local base_obj='{issue: $issue, status: $status, session: $session, timestamp: $timestamp}'
    
    if [[ -n "$error_message" && -n "$session_label" ]]; then
        jq "${base_args[@]}" \
            --arg error "$error_message" \
            --arg label "$session_label" \
            "$base_obj | . + {error_message: \$error, session_label: \$label}"
    elif [[ -n "$error_message" ]]; then
        jq "${base_args[@]}" \
            --arg error "$error_message" \
            "$base_obj | . + {error_message: \$error}"
    elif [[ -n "$session_label" ]]; then
        jq "${base_args[@]}" \
            --arg label "$session_label" \
            "$base_obj | . + {session_label: \$label}"
    else
        jq "${base_args[@]}" "$base_obj"
    fi
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
    
    # JSONを構築（jqがあれば使用、なければフォールバック）
    local json
    if command -v jq &>/dev/null; then
        json="$(build_json_with_jq "$issue_number" "$status" "$session_name" "$timestamp" "$error_message" "$session_label")"
    else
        json="$(build_json_fallback "$issue_number" "$status" "$session_name" "$timestamp" "$error_message" "$session_label")"
    fi
    
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
    if declare -f mux_generate_session_name > /dev/null 2>&1; then
        session_name="$(mux_generate_session_name "$issue")"
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
# Watcher PID Management (Issue #693)
# =============================================================================

# Watcher PIDを保存
# 引数:
#   $1 - issue_number: Issue番号
#   $2 - pid: Watcher プロセスID
save_watcher_pid() {
    local issue_number="$1"
    local pid="$2"
    
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local pid_file="${status_dir}/${issue_number}.watcher.pid"
    
    # Atomic write: write to temp file and rename
    local tmp_file="${pid_file}.tmp.$$"
    echo "$pid" > "$tmp_file"
    mv -f "$tmp_file" "$pid_file"
    log_debug "Saved watcher PID for issue #$issue_number: $pid"
}

# Watcher PIDを読み込み
# 引数:
#   $1 - issue_number: Issue番号
# 出力: PID（存在しなければ空）
load_watcher_pid() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local pid_file="${status_dir}/${issue_number}.watcher.pid"
    
    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    fi
}

# Watcher PIDファイルを削除
# 引数:
#   $1 - issue_number: Issue番号
remove_watcher_pid() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local pid_file="${status_dir}/${issue_number}.watcher.pid"
    
    if [[ -f "$pid_file" ]]; then
        rm -f "$pid_file"
        log_debug "Removed watcher PID file for issue #$issue_number"
    fi
}

# Watcherが実行中かチェック
# 引数:
#   $1 - issue_number: Issue番号
# 終了コード: 0 (実行中), 1 (停止中または不明)
is_watcher_running() {
    local issue_number="$1"
    local pid
    pid="$(load_watcher_pid "$issue_number")"
    
    if [[ -z "$pid" ]]; then
        return 1
    fi
    
    # daemon.shのis_daemon_running関数を使用
    # Note: daemon.shがロードされていることを前提とする
    if declare -f is_daemon_running > /dev/null 2>&1; then
        is_daemon_running "$pid"
    else
        # フォールバック: killコマンドでチェック
        kill -0 "$pid" 2>/dev/null
    fi
}

# =============================================================================
# Cleanup Lock Management (Issue #1077)
# Prevents race conditions between sweep.sh and watch-session.sh
# =============================================================================

# Acquire cleanup lock for an issue
# 引数:
#   $1 - issue_number: Issue番号
# 終了コード: 0 (成功), 1 (ロック取得失敗)
acquire_cleanup_lock() {
    local issue_number="$1"
    
    init_status_dir
    
    local status_dir
    status_dir="$(get_status_dir)"
    local lock_file="${status_dir}/${issue_number}.cleanup.lock"
    
    # mkdir を使ったアトミックなロック取得
    if mkdir "$lock_file" 2>/dev/null; then
        echo $$ > "$lock_file/pid"
        log_debug "Acquired cleanup lock for issue #$issue_number (PID: $$)"
        return 0
    fi
    
    # 既にロック済み - stale lockチェック
    local pid
    pid=$(cat "$lock_file/pid" 2>/dev/null) || pid=""
    
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        # stale lock - PIDファイルを上書きしてロック所有権を主張
        # rm + mkdir ではなく、PIDの上書きで原子的に所有権を移転（TOCTOU回避）
        if echo $$ > "$lock_file/pid" 2>/dev/null; then
            # PID書き込み成功後、実際に自分のPIDか再確認（別プロセスも上書きした可能性）
            local new_pid
            new_pid=$(cat "$lock_file/pid" 2>/dev/null) || new_pid=""
            if [[ "$new_pid" == "$$" ]]; then
                log_debug "Acquired cleanup lock for issue #$issue_number (took over stale lock from PID: $pid)"
                return 0
            fi
            log_debug "Failed to acquire cleanup lock for issue #$issue_number (race condition, got PID: $new_pid)"
            return 1
        fi
        # PIDファイルへの書き込みに失敗した場合はディレクトリごと作り直す
        rm -rf "$lock_file"
        if mkdir "$lock_file" 2>/dev/null; then
            echo $$ > "$lock_file/pid"
            log_debug "Acquired cleanup lock for issue #$issue_number after stale cleanup (PID: $$)"
            return 0
        fi
        log_debug "Failed to acquire cleanup lock for issue #$issue_number (race condition during recovery)"
        return 1
    fi
    
    log_debug "Failed to acquire cleanup lock for issue #$issue_number (held by PID: $pid)"
    return 1
}

# Release cleanup lock for an issue
# 引数:
#   $1 - issue_number: Issue番号
release_cleanup_lock() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local lock_file="${status_dir}/${issue_number}.cleanup.lock"
    
    if [[ -d "$lock_file" ]]; then
        # 自分のロックか確認
        local lock_pid
        lock_pid=$(cat "$lock_file/pid" 2>/dev/null) || lock_pid=""
        
        # Check if it's our lock or the process is dead
        local can_release=false
        if [[ "$lock_pid" == "$$" ]]; then
            can_release=true
        elif [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            can_release=true
        fi
        
        if [[ "$can_release" == "true" ]]; then
            # 自分のロック、または既にプロセスが死んでいる場合のみ削除
            rm -rf "$lock_file"
            log_debug "Released cleanup lock for issue #$issue_number"
        else
            log_warn "Cannot release cleanup lock for issue #$issue_number: owned by PID $lock_pid"
        fi
    else
        log_debug "No cleanup lock to release for issue #$issue_number"
    fi
}

# Check if cleanup lock exists for an issue
# 引数:
#   $1 - issue_number: Issue番号
# 終了コード: 0 (ロック存在), 1 (ロック無し)
is_cleanup_locked() {
    local issue_number="$1"
    
    local status_dir
    status_dir="$(get_status_dir)"
    local lock_file="${status_dir}/${issue_number}.cleanup.lock"
    
    if [[ -d "$lock_file" ]]; then
        # PIDファイルが存在し、プロセスが生きているか確認
        local pid
        pid=$(cat "$lock_file/pid" 2>/dev/null) || pid=""
        
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0  # ロック有効
        else
            # stale lock
            log_debug "Detected stale cleanup lock for issue #$issue_number (PID: $pid)"
            return 1
        fi
    fi
    
    return 1  # ロック無し
}
