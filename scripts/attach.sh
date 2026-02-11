#!/usr/bin/env bash
# ============================================================================
# attach.sh - Attach to a tmux session
#
# Connects to an existing pi-issue-runner tmux session by session name
# or issue number.
#
# Usage: ./scripts/attach.sh <session-name|issue-number>
#
# Arguments:
#   session-name    tmux session name (e.g., pi-issue-42)
#   issue-number    GitHub Issue number (e.g., 42)
#
# Options:
#   -h, --help      Show help message
#
# Exit codes:
#   0 - Successfully attached to session
#   1 - Session not found or error occurred
#
# Examples:
#   ./scripts/attach.sh pi-issue-42
#   ./scripts/attach.sh 42
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
source "$SCRIPT_DIR/../lib/session-resolver.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name|issue-number>

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -h, --help      このヘルプを表示

Examples:
    $(basename "$0") pi-issue-42
    $(basename "$0") 42
EOF
}

main() {
    local target=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
                target="$1"
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
    local session_name
    IFS=$'\t' read -r _ session_name < <(resolve_session_target "$target")

    log_info "Attaching to session: $session_name"
    mux_attach_session "$session_name"
}

main "$@"
