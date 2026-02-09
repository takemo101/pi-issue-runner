#!/usr/bin/env bash
# hooks.sh - イベントhook実行
#
# セッションのライフサイクルイベントでカスタムスクリプトを実行する。
# 対応イベント: on_start, on_success, on_error, on_cleanup,
#              on_improve_start, on_improve_end, on_iteration_start,
#              on_iteration_end, on_review_complete

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_HOOKS_SH_SOURCED:-}" ]]; then
    return 0
fi
_HOOKS_SH_SOURCED="true"

_HOOKS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリの読み込み（未読み込みの場合のみ）
if ! declare -f yaml_get &>/dev/null; then
    source "$_HOOKS_LIB_DIR/yaml.sh"
fi

if ! declare -f get_config &>/dev/null; then
    source "$_HOOKS_LIB_DIR/config.sh"
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
# Events: on_start, on_success, on_error, on_cleanup,
#         on_improve_start, on_improve_end, on_iteration_start,
#         on_iteration_end, on_review_complete
# Returns: hookの値（スクリプトパスまたはインラインコマンド）
get_hook() {
    local event="$1"
    
    # 設定ファイルを読み込み（未読み込みの場合）
    load_config 2>/dev/null || true
    
    # 設定から取得（環境変数オーバーライド対応）
    get_config "hooks_${event}" || echo ""
}

# ===================
# サニタイズ
# ===================

# hook環境変数の値をサニタイズ
# Usage: _sanitize_hook_env_value <value>
# 改行、タブ、ヌル文字などの制御文字を除去し、安全な文字列を返す
_sanitize_hook_env_value() {
    local value="$1"
    
    # 制御文字を除去（改行、タブ、ヌル文字等）
    # tr -d でASCII制御文字（0x00-0x1F, 0x7F）を削除
    # ただし、スペース（0x20）は保持
    printf '%s' "$value" | tr -d '\000-\037\177'
}

# ===================
# Hook 実行
# ===================

# hookを実行
# Usage: run_hook <event> <issue_number> <session_name> [branch_name] [worktree_path] [error_message] [exit_code] [issue_title] [iteration] [max_iterations] [issues_created] [issues_succeeded] [issues_failed] [review_issues_count]
run_hook() {
    local event="$1"
    local issue_number="${2:-}"
    local session_name="${3:-}"
    local branch_name="${4:-}"
    local worktree_path="${5:-}"
    local error_message="${6:-}"
    local exit_code="${7:-0}"
    local issue_title="${8:-}"
    local iteration="${9:-}"
    local max_iterations="${10:-}"
    local issues_created="${11:-}"
    local issues_succeeded="${12:-}"
    local issues_failed="${13:-}"
    local review_issues_count="${14:-}"
    
    local hook
    hook="$(get_hook "$event")"
    
    if [[ -z "$hook" ]]; then
        # hookが設定されていない場合はデフォルト動作
        _run_default_hook "$event" "$issue_number" "$session_name" "$error_message"
        return 0
    fi
    
    log_info "Running hook for event: $event"
    
    # 環境変数を設定（セッション関連）
    # ユーザー由来の値はサニタイズしてから export
    if [[ -n "$issue_number" ]]; then
        export PI_ISSUE_NUMBER="$issue_number"
    fi
    if [[ -n "$issue_title" ]]; then
        local sanitized_title
        sanitized_title="$(_sanitize_hook_env_value "$issue_title")"
        export PI_ISSUE_TITLE="$sanitized_title"
    fi
    if [[ -n "$session_name" ]]; then
        export PI_SESSION_NAME="$session_name"
    fi
    if [[ -n "$branch_name" ]]; then
        export PI_BRANCH_NAME="$branch_name"
    fi
    if [[ -n "$worktree_path" ]]; then
        export PI_WORKTREE_PATH="$worktree_path"
    fi
    if [[ -n "$error_message" ]]; then
        local sanitized_error
        sanitized_error="$(_sanitize_hook_env_value "$error_message")"
        export PI_ERROR_MESSAGE="$sanitized_error"
    fi
    export PI_EXIT_CODE="$exit_code"
    
    # 環境変数を設定（improve関連）
    if [[ -n "$iteration" ]]; then
        export PI_ITERATION="$iteration"
    fi
    if [[ -n "$max_iterations" ]]; then
        export PI_MAX_ITERATIONS="$max_iterations"
    fi
    if [[ -n "$issues_created" ]]; then
        export PI_ISSUES_CREATED="$issues_created"
    fi
    if [[ -n "$issues_succeeded" ]]; then
        export PI_ISSUES_SUCCEEDED="$issues_succeeded"
    fi
    if [[ -n "$issues_failed" ]]; then
        export PI_ISSUES_FAILED="$issues_failed"
    fi
    if [[ -n "$review_issues_count" ]]; then
        export PI_REVIEW_ISSUES_COUNT="$review_issues_count"
    fi
    
    # hook実行（テンプレート展開は非推奨、環境変数を使用）
    local hook_result=0
    _execute_hook "$hook" || hook_result=$?
    
    if [[ $hook_result -eq 0 ]]; then
        log_info "Hook completed for event: $event"
    elif [[ $hook_result -eq 2 ]]; then
        # インラインhookがブロックされた場合、デフォルト動作にフォールバック
        log_info "Falling back to default notification for event: $event"
        _run_default_hook "$event" "$issue_number" "$session_name" "$error_message"
    else
        # hookスクリプト/コマンドが失敗した場合もフォールバック
        log_warn "Hook execution failed for event: $event (exit code: $hook_result)"
        log_info "Falling back to default notification for event: $event"
        _run_default_hook "$event" "$issue_number" "$session_name" "$error_message"
    fi
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
    
    # インラインコマンドの場合: 設定または環境変数で許可が必要
    local allow_inline="${PI_RUNNER_HOOKS_ALLOW_INLINE:-${PI_RUNNER_ALLOW_INLINE_HOOKS:-}}"
    if [[ -z "$allow_inline" ]]; then
        # 環境変数未設定の場合、設定ファイルの hooks.allow_inline を確認
        allow_inline="$(get_config hooks_allow_inline)" || allow_inline="false"
    fi
    
    if [[ "$allow_inline" != "true" ]]; then
        log_warn "Inline hook commands are disabled. Falling back to default notification."
        log_warn "To enable, add 'hooks.allow_inline: true' to .pi-runner.yaml"
        log_warn "  or set: export PI_RUNNER_HOOKS_ALLOW_INLINE=true"
        log_debug "Blocked hook: $hook"
        return 2  # 2 = blocked, triggers fallback to default notification
    fi
    
    # インラインコマンドとして実行（bash -c を使用、eval は使用しない）
    # 環境変数は既に run_hook で設定済み
    log_debug "Executing inline hook command"
    bash -c "$hook"
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
        on_start|on_cleanup|on_improve_start|on_improve_end|on_iteration_start|on_iteration_end|on_review_complete)
            # デフォルトでは何もしない
            log_debug "No default action for event: $event"
            ;;
        *)
            log_warn "Unknown hook event: $event"
            ;;
    esac
}
