#!/usr/bin/env bash
# improve.sh - Continuous improvement (recursive approach)
# pi handles Issue creation and run.sh execution, improve.sh manages monitoring and loops

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"

DEFAULT_MAX_ITERATIONS=3
DEFAULT_MAX_ISSUES=5
DEFAULT_TIMEOUT=3600
DEFAULT_SESSION_WAIT_RETRIES=10
DEFAULT_SESSION_WAIT_INTERVAL=2

# Completion markers
MARKER_COMPLETE="###TASK_COMPLETE###"
MARKER_NO_ISSUES="###NO_ISSUES###"

# Run pi with completion marker detection
# Arguments:
#   $1 - prompt to send to pi
#   $2 - pi command path
# Returns:
#   0 - Issue created (TASK_COMPLETE marker detected)
#   1 - No issues found (NO_ISSUES marker detected)
#   0 - pi exited normally without marker
run_pi_with_completion_detection() {
    local prompt="$1"
    local pi_command="$2"
    local output_file
    output_file=$(mktemp)
    local pi_pid
    
    # Trap for cleanup on interrupt
    trap 'rm -f "$output_file"; kill "$pi_pid" 2>/dev/null || true' INT TERM
    
    # Run pi in background, output to both terminal and file
    # Use stdbuf to disable buffering for real-time output
    if command -v stdbuf &>/dev/null; then
        stdbuf -oL "$pi_command" --message "$prompt" 2>&1 | tee "$output_file" &
    else
        "$pi_command" --message "$prompt" 2>&1 | tee "$output_file" &
    fi
    pi_pid=$!
    
    # Monitor for completion markers
    while kill -0 "$pi_pid" 2>/dev/null; do
        if grep -q "$MARKER_COMPLETE" "$output_file" 2>/dev/null; then
            log_info "Completion marker detected. Terminating pi..."
            kill "$pi_pid" 2>/dev/null || true
            wait "$pi_pid" 2>/dev/null || true
            rm -f "$output_file"
            trap - INT TERM
            return 0  # Issues created
        fi
        if grep -q "$MARKER_NO_ISSUES" "$output_file" 2>/dev/null; then
            log_info "No issues marker detected. Terminating pi..."
            kill "$pi_pid" 2>/dev/null || true
            wait "$pi_pid" 2>/dev/null || true
            rm -f "$output_file"
            trap - INT TERM
            return 1  # No issues
        fi
        sleep 1
    done
    
    # pi exited without marker
    rm -f "$output_file"
    trap - INT TERM
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
    Runs continuous improvement:
    1. pi creates Issues via project-review
    2. pi starts parallel execution via pi-issue-runner
    3. improve.sh monitors completion
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
        echo "Reached maximum iterations ($max_iterations)"
        exit 0
    fi

    echo ""
    echo "==============================================================="
    echo "  Continuous Improvement - Iteration $iteration/$max_iterations"
    echo "==============================================================="
    echo ""

    local pi_command
    pi_command="$(get_config pi_command)"

    # Phase 1: pi creates Issues and starts execution
    local prompt
    prompt="Execute the following steps:

1. Use the project-review skill to review the entire project
2. Create GitHub Issues for discovered problems (max ${max_issues})
3. Start parallel execution for each Issue via Pi Issue Runner:
   scripts/run.sh <issue-number> --no-attach

After completing all steps, output EXACTLY ONE of the following markers:
- If you created Issues and started run.sh: $MARKER_COMPLETE
- If no problems were found: $MARKER_NO_ISSUES

IMPORTANT: The marker must be output as a single line. This is required for automatic detection."

    echo "[PHASE 1] Reviewing and creating Issues via pi..."
    if ! run_pi_with_completion_detection "$prompt" "$pi_command"; then
        echo ""
        echo "✅ Improvement complete! No issues found."
        exit 0
    fi

    # Phase 2: Monitor session completion
    echo ""
    echo "[PHASE 2] Monitoring session completion..."
    
    # Wait for sessions to appear with retry
    # Sessions may take a few seconds to start after run.sh --no-attach
    local retry_count=0
    local sessions=""
    
    echo "Waiting for sessions to start..."
    while [[ $retry_count -lt $DEFAULT_SESSION_WAIT_RETRIES ]]; do
        sessions=$("$SCRIPT_DIR/list.sh" 2>/dev/null | grep -oE "pi-issue-[0-9]+" || true)
        if [[ -n "$sessions" ]]; then
            break
        fi
        log_debug "Waiting for sessions to start... (attempt $((retry_count + 1))/$DEFAULT_SESSION_WAIT_RETRIES)"
        sleep "$DEFAULT_SESSION_WAIT_INTERVAL"
        ((retry_count++))
    done
    
    if [[ -z "$sessions" ]]; then
        echo "No running sessions found after waiting $((DEFAULT_SESSION_WAIT_RETRIES * DEFAULT_SESSION_WAIT_INTERVAL)) seconds"
        echo ""
        echo "Improvement complete! No issues found."
        exit 0
    fi
    
    # Extract issue numbers
    local issues
    issues=$(echo "$sessions" | sed "s/pi-issue-//g" | tr "\n" " ")
    
    echo "Monitoring: $issues"
    
    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/wait-for-sessions.sh" $issues --timeout "$timeout"; then
        log_warn "Some sessions failed or timed out"
    fi

    # Phase 3: Recursive call
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
