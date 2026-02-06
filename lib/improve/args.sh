#!/usr/bin/env bash
# ============================================================================
# improve/args.sh - Command-line argument parsing for improve workflow
#
# Handles parsing of all command-line options and provides usage information.
# ============================================================================

set -euo pipefail

# Constants
readonly _IMPROVE_DEFAULT_MAX_ITERATIONS=3
readonly _IMPROVE_DEFAULT_MAX_ISSUES=5
readonly _IMPROVE_DEFAULT_TIMEOUT=3600

# ============================================================================
# Show usage information
# ============================================================================
show_improve_usage() {
    local default_log_dir=".improve-logs"
    cat << EOF
Usage: improve.sh [options]

Options:
    --max-iterations N   Max iteration count (default: $_IMPROVE_DEFAULT_MAX_ITERATIONS)
    --max-issues N       Max issues per iteration (default: $_IMPROVE_DEFAULT_MAX_ISSUES)
    --timeout N          Session completion timeout in seconds (default: $_IMPROVE_DEFAULT_TIMEOUT)
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
    improve.sh
    improve.sh --max-iterations 2 --max-issues 3
    improve.sh --timeout 1800
    improve.sh --log-dir /tmp/improve-logs
    improve.sh --label my-custom-session
    improve.sh --dry-run
    improve.sh --review-only
    improve.sh --auto-continue

Environment Variables:
    PI_COMMAND           Path to pi command (default: pi)
    LOG_LEVEL            Log level (DEBUG, INFO, WARN, ERROR)
EOF
}

# ============================================================================
# Parse command-line arguments
# Output: Sets global variables with _PARSE_ prefix
# Note: Does not handle --help/-h (handled in scripts/improve.sh)
# ============================================================================
parse_improve_arguments() {
    local max_iterations=$_IMPROVE_DEFAULT_MAX_ITERATIONS
    local max_issues=$_IMPROVE_DEFAULT_MAX_ISSUES
    local timeout=$_IMPROVE_DEFAULT_TIMEOUT
    local iteration=1
    local log_dir=""
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
                show_improve_usage >&2
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_improve_usage >&2
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                show_improve_usage >&2
                exit 1
                ;;
        esac
    done

    # Set global variables (no escaping needed - direct assignment is safe)
    _PARSE_max_iterations="$max_iterations"
    _PARSE_max_issues="$max_issues"
    _PARSE_timeout="$timeout"
    _PARSE_iteration="$iteration"
    _PARSE_log_dir="$log_dir"
    _PARSE_session_label="$session_label"
    _PARSE_dry_run="$dry_run"
    _PARSE_review_only="$review_only"
    _PARSE_auto_continue="$auto_continue"
}

# Backward compatibility: keep old function name
usage() {
    show_improve_usage "$@"
}
