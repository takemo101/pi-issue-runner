#!/usr/bin/env bash
# ============================================================================
# improve.sh - Continuous improvement script
#
# Performs continuous improvement using a 2-phase approach:
# 1. Review phase: Uses pi --print for code review
# 2. Execution phase: Uses GitHub API for issue retrieval and execution
#
# Usage: ./scripts/improve.sh [options]
#
# Options:
#   --max-iterations N   Max iteration count (default: 3)
#   --max-issues N       Max issues per iteration (default: 5)
#   --timeout N          Session completion timeout in seconds (default: 3600)
#   --iteration N        Current iteration number (internal use)
#   --log-dir DIR        Log directory (default: .improve-logs)
#   --label LABEL        Session label for Issue filtering
#   --dry-run            Review only, do not create Issues
#   --review-only        Show problems only (no Issue creation or execution)
#   --auto-continue      Auto-continue without approval
#   -v, --verbose        Show verbose logs
#   -h, --help           Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   ./scripts/improve.sh
#   ./scripts/improve.sh --max-iterations 1
#   ./scripts/improve.sh --dry-run
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/github.sh"

# Handle --help early (before main, to avoid eval issues)
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
Usage: improve.sh [options]

Options:
    --max-iterations N   Max iteration count (default: 3)
    --max-issues N       Max issues per iteration (default: 5)
    --timeout N          Session completion timeout in seconds (default: 3600)
    --iteration N        Current iteration number (internal use)
    --log-dir DIR        Log directory (default: .improve-logs in current directory)
    --label LABEL        Session label for Issue filtering (auto-generated if not specified)
    --dry-run            Review only, do not create Issues
    --review-only        Show problems only (no Issue creation or execution)
    --auto-continue      Auto-continue without approval (skip confirmation)
    -v, --verbose        Show verbose logs
    -h, --help           Show this help

Description:
    Runs continuous improvement using 2-phase approach:
    1. Runs pi --print for project review and Issue creation (auto-exits)
    2. Fetches created Issues via GitHub API (filtered by session label)
    3. Starts parallel execution via run.sh --no-attach
    4. Monitors completion via wait-for-sessions.sh
    5. Recursively starts next iteration

    Issues are tagged with a session-specific label (e.g., pi-runner-20260201-082900)
    to ensure only Issues from this session are processed, enabling safe parallel runs.

Log files:
    Pi output is saved to: .improve-logs/iteration-N-YYYYMMDD-HHMMSS.log

Examples:
    improve.sh
    improve.sh --max-iterations 1
    improve.sh --dry-run
    improve.sh --review-only
    improve.sh --auto-continue
    improve.sh --label my-session
EOF
        exit 0
    fi
done

# Constants
DEFAULT_MAX_ITERATIONS=3
DEFAULT_MAX_ISSUES=5
DEFAULT_TIMEOUT=3600
# shellcheck disable=SC2034
LOG_DIR=""  # Set in main() after load_config to use current working directory

# Global: Track active sessions for cleanup on exit
declare -a ACTIVE_ISSUE_NUMBERS=()

# Cleanup function for EXIT trap
cleanup_on_exit() {
    local exit_code=$?
    
    # Only cleanup if there are active sessions and exit is not normal
    if [[ ${#ACTIVE_ISSUE_NUMBERS[@]} -gt 0 && $exit_code -ne 0 ]]; then
        log_warn "Interrupted! Cleaning up ${#ACTIVE_ISSUE_NUMBERS[@]} active session(s)..."
        for issue in "${ACTIVE_ISSUE_NUMBERS[@]}"; do
            log_info "  Cleaning up Issue #$issue..."
            "$SCRIPT_DIR/cleanup.sh" "pi-issue-$issue" --force 2>/dev/null || true
        done
        log_info "Cleanup completed."
    fi
    
    exit $exit_code
}

# Set up trap for cleanup on interruption
trap cleanup_on_exit EXIT INT TERM

usage() {
    local default_log_dir=".improve-logs"
    cat << EOF
Usage: $(basename "$0") [options]

Options:
    --max-iterations N   Max iteration count (default: $DEFAULT_MAX_ITERATIONS)
    --max-issues N       Max issues per iteration (default: $DEFAULT_MAX_ISSUES)
    --timeout N          Session completion timeout in seconds (default: $DEFAULT_TIMEOUT)
    --iteration N        Current iteration number (internal use)
    --log-dir DIR        Log directory (default: $default_log_dir in current directory)
    --label LABEL        Session label for Issue filtering (auto-generated if not specified)
    --dry-run            Review only, do not create Issues
    --review-only        Show problems only (no Issue creation or execution)
    --auto-continue      Auto-continue without approval (skip confirmation)
    -v, --verbose        Show verbose logs
    -h, --help           Show this help

Description:
    Runs continuous improvement using 2-phase approach:
    1. Runs pi --print for project review and Issue creation (auto-exits)
    2. Fetches created Issues via GitHub API (filtered by session label)
    3. Starts parallel execution via run.sh --no-attach
    4. Monitors completion via wait-for-sessions.sh
    5. Recursively starts next iteration

    Issues are tagged with a session-specific label (e.g., pi-runner-20260201-082900)
    to ensure only Issues from this session are processed, enabling safe parallel runs.

Log files:
    Pi output is saved to: $default_log_dir/iteration-N-YYYYMMDD-HHMMSS.log

Examples:
    $(basename "$0")
    $(basename "$0") --max-iterations 2 --max-issues 3
    $(basename "$0") --timeout 1800
    $(basename "$0") --log-dir /tmp/improve-logs
    $(basename "$0") --label my-custom-session
    $(basename "$0") --dry-run
    $(basename "$0") --review-only
    $(basename "$0") --auto-continue

Environment Variables:
    PI_COMMAND           Path to pi command (default: pi)
    LOG_LEVEL            Log level (DEBUG, INFO, WARN, ERROR)
EOF
}

# ============================================================================
# Subfunction: parse_improve_arguments
# Purpose: Parse command-line arguments
# Output: Shell variable assignments (eval-able)
# Note: Does not handle --help/-h (handled in main before calling this)
# ============================================================================
parse_improve_arguments() {
    local max_iterations=$DEFAULT_MAX_ITERATIONS
    local max_issues=$DEFAULT_MAX_ISSUES
    local timeout=$DEFAULT_TIMEOUT
    local iteration=1
    local log_dir=".improve-logs"
    local session_label=""
    local dry_run=false
    local review_only=false
    local auto_continue=false

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
            --log-dir)
                log_dir="$2"
                shift 2
                ;;
            --label)
                session_label="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --review-only)
                review_only=true
                shift
                ;;
            --auto-continue)
                auto_continue=true
                shift
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -h|--help)
                # Should not reach here (handled before main)
                usage >&2
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

    # Output variable assignments
    echo "local max_iterations=$max_iterations"
    echo "local max_issues=$max_issues"
    echo "local timeout=$timeout"
    echo "local iteration=$iteration"
    echo "local log_dir='$log_dir'"
    echo "local session_label='$session_label'"
    echo "local dry_run=$dry_run"
    echo "local review_only=$review_only"
    echo "local auto_continue=$auto_continue"
}

# ============================================================================
# Subfunction: setup_improve_environment
# Purpose: Setup environment and validate configuration
# Arguments: $1=iteration, $2=max_iterations, $3=session_label, $4=log_dir, $5=dry_run, $6=review_only
# Output: Shell variable assignments (eval-able)
# ============================================================================
setup_improve_environment() {
    local iteration="$1"
    local max_iterations="$2"
    local session_label="$3"
    local log_dir="$4"
    local dry_run="$5"
    local review_only="$6"

    load_config
    check_dependencies || exit 1

    # Max iterations check
    if [[ $iteration -gt $max_iterations ]]; then
        echo "" >&2
        echo "🏁 Maximum iterations ($max_iterations) reached" >&2
        exit 0
    fi

    # Generate session label if not provided
    if [[ -z "$session_label" ]]; then
        session_label="$(generate_session_label)"
        log_debug "Generated session label: $session_label"
    fi

    # Create session label in GitHub (skip for dry-run/review-only modes)
    if [[ "$dry_run" != "true" && "$review_only" != "true" ]]; then
        create_label_if_not_exists "$session_label" "pi-issue-runner session: $session_label" || true
    fi

    # Create log directory
    mkdir -p "$log_dir"
    local log_file
    log_file="$log_dir/iteration-${iteration}-$(date +%Y%m%d-%H%M%S).log"

    # Display header (to stderr, not evaluated)
    {
        echo ""
        echo "=== Continuous Improvement - Iteration $iteration/$max_iterations ==="
        echo ""
        echo "Session label: $session_label"
        echo "Log file: $log_file"
        echo ""
    } >&2

    # Output variables (to stdout, for eval)
    echo "local session_label='$session_label'"
    echo "local log_file='$log_file'"
    echo "local start_time='$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
}

# ============================================================================
# Subfunction: run_review_phase
# Purpose: Execute project review using pi --print
# Arguments: $1=max_issues, $2=session_label, $3=log_file, $4=dry_run, $5=review_only
# ============================================================================
run_review_phase() {
    local max_issues="$1"
    local session_label="$2"
    local log_file="$3"
    local dry_run="$4"
    local review_only="$5"

    local pi_command
    pi_command="$(get_config pi_command)"

    local prompt
    if [[ "$dry_run" == "true" || "$review_only" == "true" ]]; then
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題を報告してください（最大${max_issues}件）。
【重要】GitHub Issueは作成しないでください。問題の一覧を表示するのみにしてください。
問題が見つからない場合は「問題は見つかりませんでした」と報告してください。"
        echo "[PHASE 1] Running project review via pi --print (dry-run mode)..."
    else
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題からGitHub Issueを作成してください（最大${max_issues}件）。
【重要】Issueを作成する際は、必ず '--label ${session_label}' オプションを使用してラベル '${session_label}' を付けてください。
例: gh issue create --title \"...\" --body \"...\" --label \"${session_label}\"
Issueを作成しない場合は「問題は見つかりませんでした」と報告してください。"
        echo "[PHASE 1] Running project review via pi --print..."
    fi
    echo "[PHASE 1] This may take a few minutes..."
    
    if ! "$pi_command" --print --message "$prompt" 2>&1 | tee "$log_file"; then
        log_warn "pi command returned non-zero exit code"
    fi
    
    echo ""
    echo "[PHASE 1] Review complete. Log saved to: $log_file"

    # Exit early for review-only or dry-run modes
    if [[ "$review_only" == "true" ]]; then
        echo ""
        echo "✅ Review-only mode complete. See log for details: $log_file"
        exit 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "✅ Dry-run mode complete. No Issues were created."
        echo "   Review results saved to: $log_file"
        exit 0
    fi
}

# ============================================================================
# Subfunction: fetch_created_issues
# Purpose: Fetch issues created during review phase
# Arguments: $1=start_time, $2=max_issues, $3=session_label
# Output: Issue numbers (one per line) to stdout
# Note: All log messages go to stderr to prevent pollution of output
# ============================================================================
fetch_created_issues() {
    local start_time="$1"
    local max_issues="$2"
    local session_label="$3"

    echo "" >&2
    echo "[PHASE 2] Fetching Issues created after $start_time with label '$session_label'..." >&2
    
    local issues
    issues=$(get_issues_created_after "$start_time" "$max_issues" "$session_label") || true
    
    if [[ -z "$issues" ]]; then
        echo "No new Issues created" >&2
        echo "" >&2
        echo "✅ Improvement complete! No issues found." >&2
        exit 0
    fi
    
    # Convert Issue numbers to array and validate
    local issue_array=()
    while IFS= read -r issue; do
        if [[ -n "$issue" && "$issue" =~ ^[0-9]+$ ]]; then
            issue_array+=("$issue")
        fi
    done <<< "$issues"
    
    if [[ ${#issue_array[@]} -eq 0 ]]; then
        echo "No new Issues created" >&2
        echo "" >&2
        echo "✅ Improvement complete! No issues found." >&2
        exit 0
    fi
    
    echo "Created Issues: ${issue_array[*]}" >&2
    
    # Output issue numbers (to stdout for capture)
    printf "%s\n" "${issue_array[@]}"
}

# ============================================================================
# Subfunction: execute_issues_in_parallel
# Purpose: Start parallel execution of issues
# Arguments: $1=newline-separated issue numbers
# ============================================================================
execute_issues_in_parallel() {
    local issues="$1"
    
    echo ""
    echo "[PHASE 3] Starting parallel execution..."
    
    if [[ -z "$issues" ]]; then
        echo "  No issues to execute"
        return 0
    fi
    
    while IFS= read -r issue; do
        [[ -z "$issue" ]] && continue
        echo "  Starting Issue #$issue..."
        if "$SCRIPT_DIR/run.sh" "$issue" --no-attach; then
            # Track active session for cleanup on interruption
            ACTIVE_ISSUE_NUMBERS+=("$issue")
        else
            log_warn "Failed to start session for Issue #$issue"
        fi
    done <<< "$issues"
}

# ============================================================================
# Subfunction: wait_for_completion
# Purpose: Wait for all sessions to complete
# Arguments: $1=timeout
# ============================================================================
wait_for_completion() {
    local timeout="$1"

    echo ""
    echo "[PHASE 4] Waiting for sessions to complete..."
    
    if [[ ${#ACTIVE_ISSUE_NUMBERS[@]} -eq 0 ]]; then
        echo "  No active sessions to wait for"
        return 0
    fi
    
    echo "  Waiting for: ${ACTIVE_ISSUE_NUMBERS[*]}"
    
    if ! "$SCRIPT_DIR/wait-for-sessions.sh" "${ACTIVE_ISSUE_NUMBERS[@]}" --timeout "$timeout" --cleanup; then
        log_warn "Some sessions failed or timed out"
    fi
    
    # Clear active sessions after completion
    ACTIVE_ISSUE_NUMBERS=()
}

# ============================================================================
# Subfunction: start_next_iteration
# Purpose: Start next iteration with updated parameters
# Arguments: Multiple (see function body)
# ============================================================================
start_next_iteration() {
    local iteration="$1"
    local max_iterations="$2"
    local max_issues="$3"
    local timeout="$4"
    local log_dir="$5"
    local session_label="$6"
    local auto_continue="$7"

    echo ""
    echo "[PHASE 5] Starting next iteration..."
    
    # Confirmation before continuing (unless --auto-continue is set)
    if [[ "$auto_continue" != "true" ]]; then
        echo ""
        echo "Press Enter to continue to iteration $((iteration + 1)), or Ctrl+C to abort..."
        read -r
    fi
    
    # Build arguments for recursive call
    local args=(
        --max-iterations "$max_iterations"
        --max-issues "$max_issues"
        --timeout "$timeout"
        --log-dir "$log_dir"
        --iteration "$((iteration + 1))"
        --label "$session_label"
    )
    
    # Preserve --auto-continue flag
    if [[ "$auto_continue" == "true" ]]; then
        args+=(--auto-continue)
    fi
    
    exec "$0" "${args[@]}"
}

# ============================================================================
# Main function
# Purpose: Orchestrate continuous improvement workflow
# ============================================================================
main() {
    # Parse arguments
    eval "$(parse_improve_arguments "$@")"
    
    # Setup environment
    eval "$(setup_improve_environment "$iteration" "$max_iterations" "$session_label" "$log_dir" "$dry_run" "$review_only")"
    
    # Phase 1: Review
    run_review_phase "$max_issues" "$session_label" "$log_file" "$dry_run" "$review_only"
    
    # Phase 2: Fetch issues
    local created_issues
    created_issues="$(fetch_created_issues "$start_time" "$max_issues" "$session_label")"
    
    # Phase 3: Execute in parallel
    execute_issues_in_parallel "$created_issues"
    
    # Phase 4: Wait for completion
    wait_for_completion "$timeout"
    
    # Phase 5: Next iteration
    start_next_iteration "$iteration" "$max_iterations" "$max_issues" "$timeout" "$log_dir" "$session_label" "$auto_continue"
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

    # gh command
    if ! command -v gh &> /dev/null; then
        missing+=("gh (GitHub CLI)")
    fi

    # jq command (required for GitHub API parsing)
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
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
