#!/usr/bin/env bash
# notify.sh - 通知とステータス管理

set -euo pipefail

_NOTIFY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_NOTIFY_LIB_DIR/config.sh"
source "$_NOTIFY_LIB_DIR/log.sh"
source "$_NOTIFY_LIB_DIR/status.sh"

# 後方互換性のために以下の関数はstatus.shで定義済み:
# - get_status_dir()
# - init_status_dir()
# - save_status()
# - load_status()
# - get_status_value()
# - get_error_message()
# - remove_status()
# - set_status()     (新規)
# - get_status()     (新規)
# - list_all_statuses()  (新規)
# - list_issues_by_status()  (新規)

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
    local attach_script="${_NOTIFY_LIB_DIR}/../scripts/attach.sh"
    
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

# Note: handle_error and handle_complete were removed in Issue #883
# These functions are now implemented in scripts/watch-session.sh
# This library provides helper functions for notifications only:
#   - notify_error
#   - notify_success
#   - open_terminal_and_attach
