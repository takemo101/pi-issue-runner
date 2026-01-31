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
                LOG_LEVEL="DEBUG"
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
4. After starting all Issues, output ###TASK_COMPLETE### and exit

Note: If no problems are found, report 'no issues' and output ###TASK_COMPLETE###."

    echo "[PHASE 1] Reviewing and creating Issues via pi..."
    "$pi_command" --message "$prompt" || {
        log_warn "pi command exited with non-zero status"
    }

    # Phase 2: Monitor session completion
    echo ""
    echo "[PHASE 2] Monitoring session completion..."
    
    # Get running sessions
    local sessions
    sessions=$("$SCRIPT_DIR/list.sh" 2>/dev/null | grep -oE "pi-issue-[0-9]+" || true)
    
    if [[ -z "$sessions" ]]; then
        echo "No running sessions found"
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
