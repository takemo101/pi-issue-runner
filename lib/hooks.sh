#!/usr/bin/env bash
# hooks.sh - イベントhook実行
#
# セッションのライフサイクルイベントでカスタムスクリプトを実行する。
# 対応イベント: on_start, on_success, on_error, on_cleanup

set -euo pipefail

_HOOKS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリの読み込み（未読み込みの場合のみ）
if ! declare -f yaml_get &>/dev/null; then
    source "$_HOOKS_LIB_DIR/yaml.sh"
fi

if ! declare -f log_info &>/dev/null; then
    source "$_HOOKS_LIB_DIR/log.sh"
fi

if ! declare -f notify_success &>/dev/null; then
    source "$_HOOKS_LIB_DIR/notify.sh"
fi

# ===================
# Hook 設定取得
# ===================

# hook設定を取得
# Usage: get_hook <event>
# Events: on_start, on_success, on_error, on_cleanup
# Returns: hookの値（スクリプトパスまたはインラインコマンド）
get_hook() {
    local event="$1"
    
    # 設定ファイルを探す
    local config_file
    if config_file="$(find_config_file "$(pwd)" 2>/dev/null)"; then
        yaml_get "$config_file" ".hooks.$event" ""
    else
        echo ""
    fi
}

# ===================
# Hook 実行
# ===================

# hookを実行
# Usage: run_hook <event> <issue_number> <session_name> [branch_name] [worktree_path] [error_message] [exit_code] [issue_title]
run_hook() {
    local event="$1"
    local issue_number="$2"
    local session_name="$3"
    local branch_name="${4:-}"
    local worktree_path="${5:-}"
    local error_message="${6:-}"
    local exit_code="${7:-0}"
    local issue_title="${8:-}"
    
    local hook
    hook="$(get_hook "$event")"
    
    if [[ -z "$hook" ]]; then
        # hookが設定されていない場合はデフォルト動作
        _run_default_hook "$event" "$issue_number" "$session_name" "$error_message"
        return 0
    fi
    
    log_info "Running hook for event: $event"
    
    # 環境変数を設定
    export PI_ISSUE_NUMBER="$issue_number"
    export PI_ISSUE_TITLE="$issue_title"
    export PI_SESSION_NAME="$session_name"
    export PI_BRANCH_NAME="$branch_name"
    export PI_WORKTREE_PATH="$worktree_path"
    export PI_ERROR_MESSAGE="$error_message"
    export PI_EXIT_CODE="$exit_code"
    
    # テンプレート変数を展開
    hook="$(_expand_hook_template "$hook" "$issue_number" "$issue_title" "$session_name" "$branch_name" "$worktree_path" "$error_message" "$exit_code")"
    
    # hook実行
    _execute_hook "$hook" || {
        log_warn "Hook execution failed for event: $event"
        return 0  # hookの失敗でメイン処理を止めない
    }
    
    log_info "Hook completed for event: $event"
}

# テンプレート変数を展開
_expand_hook_template() {
    local hook="$1"
    local issue_number="$2"
    local issue_title="$3"
    local session_name="$4"
    local branch_name="$5"
    local worktree_path="$6"
    local error_message="$7"
    local exit_code="$8"
    
    # Bash文字列置換を使用（sedより安全）
    hook="${hook//\{\{issue_number\}\}/$issue_number}"
    hook="${hook//\{\{issue_title\}\}/$issue_title}"
    hook="${hook//\{\{session_name\}\}/$session_name}"
    hook="${hook//\{\{branch_name\}\}/$branch_name}"
    hook="${hook//\{\{worktree_path\}\}/$worktree_path}"
    hook="${hook//\{\{error_message\}\}/$error_message}"
    hook="${hook//\{\{exit_code\}\}/$exit_code}"
    
    echo "$hook"
}

# hookを実行（ファイルまたはインラインコマンド）
_execute_hook() {
    local hook="$1"
    
    # ファイルパスの場合（スクリプトファイル）
    if [[ -f "$hook" ]]; then
        log_debug "Executing hook script: $hook"
        if [[ -x "$hook" ]]; then
            "$hook"
        else
            bash "$hook"
        fi
        return $?
    fi
    
    # インラインコマンドとして実行
    log_warn "Executing inline hook command (security note: ensure this is from a trusted source)"
    log_debug "Executing inline hook"
    eval "$hook"
}

# ===================
# デフォルト動作
# ===================

# デフォルトhook（notify.sh相当の動作）
_run_default_hook() {
    local event="$1"
    local issue_number="$2"
    local session_name="$3"
    local error_message="${4:-}"
    
    case "$event" in
        on_success)
            notify_success "$session_name" "$issue_number"
            ;;
        on_error)
            notify_error "$session_name" "$issue_number" "$error_message"
            ;;
        on_start|on_cleanup)
            # デフォルトでは何もしない
            log_debug "No default action for event: $event"
            ;;
        *)
            log_warn "Unknown hook event: $event"
            ;;
    esac
}
