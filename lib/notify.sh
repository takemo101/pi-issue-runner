#!/usr/bin/env bash
# notify.sh - 通知とステータス管理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/log.sh"

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
    local session_name="$3"
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

# macOSかどうかチェック
is_macos() {
    [[ "$(uname)" == "Darwin" ]]
}

# Linuxかどうかチェック
is_linux() {
    [[ "$(uname)" == "Linux" ]]
}

# 通知を表示（エラー用）
# 引数:
#   $1 - session_name: セッション名
#   $2 - issue_number: Issue番号
#   $3 - error_message: エラーメッセージ (オプション)
notify_error() {
    local session_name="$1"
    local issue_number="$2"
    local error_message="${3:-エラーが発生しました}"
    
    log_info "Sending error notification for session: $session_name"
    
    if is_macos; then
        # macOS: osascriptを使用
        # エラーメッセージをAppleScript用にエスケープ
        local escaped_message
        escaped_message="$(echo "$error_message" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 200)"
        
        osascript -e "display notification \"$escaped_message\" with title \"Pi Issue Runner\" subtitle \"Issue #$issue_number でエラー\" sound name \"Basso\"" 2>/dev/null || {
            log_warn "Failed to send macOS notification"
        }
    elif is_linux; then
        # Linux: notify-sendを使用（利用可能な場合）
        if command -v notify-send &> /dev/null; then
            notify-send -u critical "Pi Issue Runner" "Issue #$issue_number でエラー: $error_message" 2>/dev/null || {
                log_warn "Failed to send Linux notification"
            }
        else
            log_warn "notify-send not available, skipping notification"
        fi
    else
        log_warn "Notification not supported on this platform"
    fi
}

# 成功通知を表示
# 引数:
#   $1 - session_name: セッション名
#   $2 - issue_number: Issue番号
notify_success() {
    local session_name="$1"
    local issue_number="$2"
    
    log_info "Sending success notification for session: $session_name"
    
    if is_macos; then
        osascript -e "display notification \"タスクが正常に完了しました\" with title \"Pi Issue Runner\" subtitle \"Issue #$issue_number 完了\" sound name \"Glass\"" 2>/dev/null || {
            log_warn "Failed to send macOS notification"
        }
    elif is_linux; then
        if command -v notify-send &> /dev/null; then
            notify-send "Pi Issue Runner" "Issue #$issue_number 完了: タスクが正常に完了しました" 2>/dev/null || {
                log_warn "Failed to send Linux notification"
            }
        fi
    fi
}

# Terminal.appを開いてセッションにアタッチ
# 引数:
#   $1 - session_name: セッション名
open_terminal_and_attach() {
    local session_name="$1"
    
    log_info "Opening Terminal and attaching to session: $session_name"
    
    if ! is_macos; then
        log_warn "open_terminal_and_attach is only supported on macOS"
        return 1
    fi
    
    # 現在のスクリプトディレクトリからattach.shのパスを計算
    local attach_script="${SCRIPT_DIR}/../scripts/attach.sh"
    
    if [[ ! -x "$attach_script" ]]; then
        log_error "attach.sh not found or not executable: $attach_script"
        return 1
    fi
    
    # Terminal.appを開いてattachコマンドを実行
    if ! osascript << EOF 2>/dev/null
tell application "Terminal"
    activate
    do script "\"$attach_script\" \"$session_name\""
end tell
EOF
    then
        log_warn "Failed to open Terminal.app"
        return 1
    fi
    
    log_info "Terminal opened and attach command sent"
}

# エラー検知時の統合処理
# 引数:
#   $1 - session_name: セッション名
#   $2 - issue_number: Issue番号
#   $3 - error_message: エラーメッセージ
#   $4 - auto_attach: 自動アタッチするか (true/false)
handle_error() {
    local session_name="$1"
    local issue_number="$2"
    local error_message="$3"
    local auto_attach="${4:-true}"
    
    log_error "Error detected in session $session_name: $error_message"
    
    # ステータスを保存
    save_status "$issue_number" "error" "$session_name" "$error_message"
    
    # 通知を表示
    notify_error "$session_name" "$issue_number" "$error_message"
    
    # 自動アタッチ
    if [[ "$auto_attach" == "true" ]] && is_macos; then
        open_terminal_and_attach "$session_name"
    fi
}

# 完了時の統合処理
# 引数:
#   $1 - session_name: セッション名
#   $2 - issue_number: Issue番号
handle_complete() {
    local session_name="$1"
    local issue_number="$2"
    
    log_info "Task completed in session: $session_name"
    
    # ステータスを保存
    save_status "$issue_number" "complete" "$session_name"
    
    # 成功通知
    notify_success "$session_name" "$issue_number"
}
