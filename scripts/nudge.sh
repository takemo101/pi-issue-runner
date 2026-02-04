#!/usr/bin/env bash
# ============================================================================
# nudge.sh - Send a continuation message to a tmux session
#
# Sends a message to an existing pi-issue-runner tmux session to prompt
# the agent to continue working on the task.
#
# Usage: ./scripts/nudge.sh <session-name|issue-number> [options]
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   -m, --message TEXT  Custom message to send (default: "続けてください")
#   -s, --session NAME  Explicitly specify session name
#   -h, --help          Show help message
#
# Exit codes:
#   0 - Message sent successfully
#   1 - Session not found or error occurred
#
# Examples:
#   ./scripts/nudge.sh 42
#   ./scripts/nudge.sh pi-issue-42
#   ./scripts/nudge.sh 42 --message "Please continue"
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

# デフォルトメッセージ
DEFAULT_MESSAGE="続けてください"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number> [options]

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -m, --message TEXT  送信するメッセージ（デフォルト: "$DEFAULT_MESSAGE"）
    -s, --session NAME  セッション名を明示的に指定
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") pi-issue-42
    $(basename "$0") 42 --message "続きをお願いします"
    $(basename "$0") --session pi-issue-42 --message "完了しましたか？"
EOF
}

# メッセージをセッションに送信
send_nudge() {
    local session_name="$1"
    local message="$2"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    log_info "Sending nudge to session: $session_name"
    log_info "Message: $message"
    
    # メッセージを送信してEnterキーを押す
    send_keys "$session_name" "$message"
    
    log_info "Nudge sent successfully"
}

main() {
    local target=""
    local message="$DEFAULT_MESSAGE"
    local session_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -m|--message)
                if [[ -z "${2:-}" ]]; then
                    log_error "Message cannot be empty"
                    usage >&2
                    exit 1
                fi
                message="$2"
                shift 2
                ;;
            -s|--session)
                if [[ -z "${2:-}" ]]; then
                    log_error "Session name cannot be empty"
                    usage >&2
                    exit 1
                fi
                session_name="$2"
                shift 2
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

    # セッション名が明示的に指定された場合
    if [[ -n "$session_name" ]]; then
        # targetが指定されている場合はエラー
        if [[ -n "$target" ]]; then
            log_error "Cannot specify both session name and issue number"
            usage >&2
            exit 1
        fi
    else
        # targetが必要
        if [[ -z "$target" ]]; then
            log_error "Session name or issue number is required"
            usage >&2
            exit 1
        fi
        
        # Issue番号かセッション名か判定
        if [[ "$target" =~ ^[0-9]+$ ]]; then
            # Issue番号からセッション名を生成
            load_config
            session_name="$(generate_session_name "$target")"
        else
            session_name="$target"
        fi
    fi

    send_nudge "$session_name" "$message"
}

main "$@"
