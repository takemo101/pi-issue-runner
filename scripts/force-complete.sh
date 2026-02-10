#!/usr/bin/env bash
# ============================================================================
# force-complete.sh - Forcefully complete a session
#
# Sends a completion or error marker to a tmux session to trigger
# watch-session.sh cleanup. Useful when the AI forgets to output the
# completion marker or when manually determining task completion.
#
# Usage: ./scripts/force-complete.sh <session-name|issue-number> [options]
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   --error             Send error marker instead of completion marker
#   --message <msg>     Add custom message
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Marker sent successfully
#   1 - Session not found or error occurred
#
# Examples:
#   ./scripts/force-complete.sh 42
#   ./scripts/force-complete.sh pi-issue-42
#   ./scripts/force-complete.sh 42 --error
#   ./scripts/force-complete.sh 42 --message "Manual completion"
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/session-resolver.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --error         エラーマーカーを送信
    --message <msg> カスタムメッセージを追加
    -h, --help      このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") pi-issue-42
    $(basename "$0") 42 --error
    $(basename "$0") 42 --message "Manual completion"
    $(basename "$0") 42 --error --message "Stopped by user"

Description:
    指定されたセッションに完了マーカーを送信し、watch-session.shによる
    自動クリーンアップをトリガーします。

    AIが完了マーカーを出力し忘れた場合や、手動でタスク完了を判断した
    場合に使用してください。
EOF
}

main() {
    local target=""
    local send_error=false
    local custom_message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --error)
                send_error=true
                shift
                ;;
            --message)
                if [[ -z "${2:-}" ]]; then
                    log_error "--message requires a value"
                    exit 1
                fi
                custom_message="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$target" ]]; then
        log_error "Session name or issue number is required"
        usage >&2
        exit 1
    fi

    load_config

    # Issue番号またはセッション名から両方を解決
    local issue_number session_name
    IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "$target")
    
    if [[ -z "$issue_number" ]]; then
        log_error "Could not extract issue number from session name: $session_name"
        exit 1
    fi

    # セッション存在確認
    if ! session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        exit 1
    fi

    # シグナルファイルを作成（最優先検出方式）
    local status_dir
    status_dir="$(get_status_dir 2>/dev/null)" || true

    if [[ -n "$status_dir" ]]; then
        mkdir -p "$status_dir"
        if [[ "$send_error" == "true" ]]; then
            local error_msg="${custom_message:-Forced error by user}"
            echo "$error_msg" > "${status_dir}/signal-error-${issue_number}"
            log_info "Created signal file: signal-error-${issue_number}"
        else
            local complete_msg="${custom_message:-Forced completion by user}"
            echo "$complete_msg" > "${status_dir}/signal-complete-${issue_number}"
            log_info "Created signal file: signal-complete-${issue_number}"
        fi
    fi

    # テキストマーカーも送信（後方互換・フォールバック）
    local marker
    if [[ "$send_error" == "true" ]]; then
        marker="###TASK_ERROR_${issue_number}###"
        log_info "Sending error marker to session: $session_name"
    else
        marker="###TASK_COMPLETE_${issue_number}###"
        log_info "Sending completion marker to session: $session_name"
    fi

    # セッションにマーカーを送信
    # echoコマンドを送信して改行を含む出力を強制
    # markerは固定形式(###TASK_COMPLETE_N###)のためダブルクォートで安全
    local escaped_marker="${marker//\"/\\\"}"
    send_keys "$session_name" "echo \"$escaped_marker\""

    # カスタムメッセージがある場合は追加送信
    # ユーザー入力のためシングルクォート・ダブルクォートの両方をエスケープ
    if [[ -n "$custom_message" ]]; then
        log_info "Sending custom message: $custom_message"
        local escaped_message="${custom_message//\"/\\\"}"
        send_keys "$session_name" "echo \"$escaped_message\""
    fi

    log_info "Marker sent. watch-session.sh will detect and cleanup."
    log_info "Session: $session_name (Issue #$issue_number)"
}

main "$@"
