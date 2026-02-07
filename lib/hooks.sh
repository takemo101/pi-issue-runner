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
    if [[ -n "$issue_number" ]]; then
        export PI_ISSUE_NUMBER="$issue_number"
    fi
    if [[ -n "$issue_title" ]]; then
        export PI_ISSUE_TITLE="$issue_title"
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
        export PI_ERROR_MESSAGE="$error_message"
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
    _execute_hook "$hook" || {
        log_warn "Hook execution failed for event: $event"
        return 0  # hookの失敗でメイン処理を止めない
    }
    
    log_info "Hook completed for event: $event"
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
    
    # インラインコマンドの場合: 明示的許可が必要
    if [[ "${PI_RUNNER_ALLOW_INLINE_HOOKS:-false}" != "true" ]]; then
        log_warn "Inline hook commands are disabled."
        log_warn "To enable, set: export PI_RUNNER_ALLOW_INLINE_HOOKS=true"
        log_warn "Hook: $hook"
        return 0
    fi
    
    # インラインコマンドとして実行（bash -c を使用、eval は使用しない）
    # 環境変数は既に run_hook で設定済み
    log_warn "Executing inline hook command (security note: ensure this is from a trusted source)"
    log_debug "Executing inline hook"
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
        on_start|on_cleanup)
            # デフォルトでは何もしない
            log_debug "No default action for event: $event"
            ;;
        *)
            log_warn "Unknown hook event: $event"
            ;;
    esac
}
