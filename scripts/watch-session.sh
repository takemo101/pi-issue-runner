#!/usr/bin/env bash
# ============================================================================
# watch-session.sh - Simple session completion watcher
#
# Responsibilities:
#   - Monitor tmux session output for TASK_COMPLETE marker
#   - Trigger cleanup on completion
#
# Usage: ./watch-session.sh <session-name>
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/multiplexer.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

# Configuration
INTERVAL=5

usage() {
    cat << EOF
Usage: $(basename "$0") <session-name>

Arguments:
    session-name    tmux session name (e.g., pi-issue-42)

Description:
    Monitor tmux session and trigger cleanup on TASK_COMPLETE marker detection.
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        log_error "Session name is required"
        usage >&2
        exit 1
    fi

    local session_name="$1"
    local issue_number="${session_name##*-}"
    
    log_info "Watching session: $session_name (Issue #$issue_number)"
    
    # Setup signal file for completion detection
    local status_dir
    status_dir="$(get_config worktree_base_dir)/.status"
    local signal_file="$status_dir/${issue_number}.signal"
    
    # Cleanup old signal file
    rm -f "$signal_file"
    
    # Main monitoring loop
    while mux_session_exists "$session_name"; do
        # Check for completion signal file (alternative detection method)
        if [[ -f "$signal_file" ]]; then
            local signal_content
            signal_content=$(cat "$signal_file" 2>/dev/null || echo "")
            if [[ "$signal_content" == *"COMPLETE"* ]]; then
                log_info "Completion signal detected via file"
                perform_cleanup "$issue_number" "$session_name"
                exit 0
            fi
        fi
        
        # Check session output for marker
        local output
        output=$(mux_get_session_output "$session_name" 100 2>/dev/null || echo "")
        
        if [[ "$output" == *"###TASK_COMPLETE_${issue_number}###"* ]]; then
            log_info "TASK_COMPLETE marker detected"
            perform_cleanup "$issue_number" "$session_name"
            exit 0
        fi
        
        if [[ "$output" == *"###TASK_ERROR_${issue_number}###"* ]]; then
            log_error "TASK_ERROR marker detected"
            exit 1
        fi
        
        sleep "$INTERVAL"
    done
    
    # Session ended without marker
    log_warn "Session ended without completion marker: $session_name"
    exit 1
}

perform_cleanup() {
    local issue_number="$1"
    local session_name="$2"
    
    log_info "Performing cleanup for Issue #$issue_number"
    
    # Stop session
    mux_kill_session "$session_name" 2>/dev/null || true
    
    # Run cleanup
    if "$SCRIPT_DIR/cleanup.sh" "$issue_number"; then
        log_info "Cleanup completed successfully"
    else
        log_error "Cleanup failed"
        exit 1
    fi
}

main "$@"
