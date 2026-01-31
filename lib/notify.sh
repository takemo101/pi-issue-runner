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
    
    # 計画書を削除（ホスト環境で実行するため確実に反映される）
    local plan_file="docs/plans/issue-${issue_number}-plan.md"
    if [[ -f "$plan_file" ]]; then
        log_info "Deleting plan file: $plan_file"
        rm -f "$plan_file"
        
        # git でコミット（失敗しても継続）
        if git rev-parse --git-dir &>/dev/null; then
            git add -A 2>/dev/null || true
            git commit -m "chore: remove plan for issue #${issue_number}" 2>/dev/null || true
            git push origin main 2>/dev/null || log_warn "Failed to push plan deletion (may need manual push)"
        fi
    else
        log_debug "No plan file found at: $plan_file"
    fi
    
    # 成功通知
    notify_success "$session_name" "$issue_number"
}
