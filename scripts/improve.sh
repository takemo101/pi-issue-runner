#!/usr/bin/env bash
# improve.sh - Continuous improvement (tmux-based approach)
# Uses tmux session for pi execution, same as run.sh/watch-session.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"

# Constants
IMPROVE_SESSION="pi-improve"
MARKER_COMPLETE="###TASK_COMPLETE###"
MARKER_NO_ISSUES="###NO_ISSUES###"

DEFAULT_MAX_ITERATIONS=3
DEFAULT_MAX_ISSUES=5
DEFAULT_TIMEOUT=3600

# Wait for marker detection using tmux capture-pane
# Arguments:
#   $1 - session: tmux session name
#   $2 - timeout: timeout in seconds
# Returns:
#   0 - Issues created (TASK_COMPLETE marker detected)
#   1 - No issues found (NO_ISSUES marker detected)
#   2 - Timeout
wait_for_marker() {
    local session="$1"
    local timeout="$2"
    local start_time
    start_time=$(date +%s)
    
    log_debug "Starting marker detection for session: $session"
    
    while tmux has-session -t "$session" 2>/dev/null; do
        local output
        output=$(tmux capture-pane -t "$session" -p -S -200 2>/dev/null) || {
            sleep 2
            continue
        }
        
        if echo "$output" | grep -qF "$MARKER_COMPLETE"; then
            log_info "Completion marker detected"
            tmux kill-session -t "$session" 2>/dev/null || true
            return 0  # Issues created
        fi
        
        if echo "$output" | grep -qF "$MARKER_NO_ISSUES"; then
            log_info "No issues marker detected"
            tmux kill-session -t "$session" 2>/dev/null || true
            return 1  # No issues
        fi
        
        # Timeout check
        local elapsed=$(( $(date +%s) - start_time ))
        if [[ $elapsed -gt $timeout ]]; then
            log_warn "Timeout waiting for marker ($timeout seconds)"
            tmux kill-session -t "$session" 2>/dev/null || true
            return 2  # Timeout
        fi
        
        sleep 2
    done
    
    # Session ended without marker
    log_debug "Session ended without marker"
    return 0
}

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --max-iterations N   Max iteration count (default: $DEFAULT_MAX_ITERATIONS)
    --max-issues N       Max issues per iteration (default: $DEFAULT_MAX_ISSUES)
    --timeout N          Session completion timeout in seconds (default: $DEFAULT_TIMEOUT)
    --iteration N        Current iteration number (internal use)
    -v, --verbose        Show verbose logs
    -h, --help           Show this help

Description:
    Runs continuous improvement using tmux-based monitoring:
    1. Creates tmux session "pi-improve" and runs pi inside
    2. pi creates Issues via project-review and starts parallel execution
    3. Monitors completion using tmux capture-pane
    4. Recursively starts next iteration on completion

Examples:
    $(basename "$0")
    $(basename "$0") --max-iterations 2 --max-issues 3
    $(basename "$0") --timeout 1800

Environment Variables:
    PI_COMMAND           Path to pi command (default: pi)
    LOG_LEVEL            Log level (DEBUG, INFO, WARN, ERROR)
EOF
}

main() {
    local max_iterations=$DEFAULT_MAX_ITERATIONS
    local max_issues=$DEFAULT_MAX_ISSUES
    local timeout=$DEFAULT_TIMEOUT
    local iteration=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-iterations)
                max_iterations="$2"
                shift 2
                ;;
            --max-issues)
                max_issues="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --iteration)
                iteration="$2"
                shift 2
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
                shift
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
                log_error "Unexpected argument: $1"
                usage >&2
                exit 1
                ;;
        esac
    done

    load_config

    # Dependency check
    check_dependencies || exit 1

    # Max iterations check
    if [[ $iteration -gt $max_iterations ]]; then
        echo ""
        echo "🏁 Maximum iterations ($max_iterations) reached"
        exit 0
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  🔧 Continuous Improvement - Iteration $iteration/$max_iterations"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local pi_command
    pi_command="$(get_config pi_command)"

    # Kill existing session if present
    if tmux has-session -t "$IMPROVE_SESSION" 2>/dev/null; then
        log_info "Removing existing session: $IMPROVE_SESSION"
        tmux kill-session -t "$IMPROVE_SESSION" 2>/dev/null || true
    fi

    # Phase 1: Create tmux session and run pi inside
    local prompt="Execute the following steps:

1. Use the project-review skill to review the entire project
2. Create GitHub Issues for discovered problems (max ${max_issues})
3. Start parallel execution for each Issue via Pi Issue Runner:
   scripts/run.sh <issue-number> --no-attach

After completing all steps, output EXACTLY ONE of the following markers:
- If you created Issues and started run.sh: $MARKER_COMPLETE
- If no problems were found: $MARKER_NO_ISSUES

IMPORTANT: The marker must be output as a single line. This is required for automatic detection."

    echo "[PHASE 1] Starting pi in tmux session..."
    
    # Create tmux session and run pi
    tmux new-session -d -s "$IMPROVE_SESSION" -x 200 -y 50 \
        "$pi_command --message \"$prompt\""
    
    echo "[PHASE 1] Monitoring for completion marker..."
    
    local marker_result=0
    wait_for_marker "$IMPROVE_SESSION" "$timeout" || marker_result=$?
    
    if [[ $marker_result -eq 1 ]]; then
        echo ""
        echo "✅ Improvement complete! No issues found."
        exit 0
    fi
    
    if [[ $marker_result -eq 2 ]]; then
        log_error "Timeout waiting for pi to complete"
        exit 1
    fi

    # Phase 2: Wait for sessions to start and monitor completion
    echo ""
    echo "[PHASE 2] Waiting for sessions to start..."
    sleep 5  # Wait for sessions to start
    
    local sessions
    sessions=$("$SCRIPT_DIR/list.sh" 2>/dev/null | grep -oE "pi-issue-[0-9]+" || true)
    
    if [[ -z "$sessions" ]]; then
        echo "No running sessions found"
        echo ""
        echo "✅ Improvement complete!"
        exit 0
    fi
    
    local issues
    issues=$(echo "$sessions" | sed "s/pi-issue-//g" | tr "\n" " ")
    
    echo "[PHASE 2] Monitoring sessions: $issues"
    
    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/wait-for-sessions.sh" $issues --timeout "$timeout"; then
        log_warn "Some sessions failed or timed out"
    fi

    # Phase 3: Recursive call for next iteration
    echo ""
    echo "[PHASE 3] Starting next iteration..."
    
    exec "$0" \
        --max-iterations "$max_iterations" \
        --max-issues "$max_issues" \
        --timeout "$timeout" \
        --iteration "$((iteration + 1))"
}

# Dependency check
check_dependencies() {
    local missing=()

    # pi command
    local pi_command
    pi_command="$(get_config pi_command)"
    if ! command -v "$pi_command" &> /dev/null; then
        missing+=("$pi_command (pi)")
    fi

    # tmux
    if ! command -v tmux &> /dev/null; then
        missing+=("tmux")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep" >&2
        done
        return 1
    fi

    return 0
}

main "$@"
