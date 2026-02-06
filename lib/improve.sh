#!/usr/bin/env bash
# ============================================================================
# improve.sh - Continuous improvement library
#
# Core functionality for continuous improvement workflow.
# Provides 2-phase approach:
# 1. Review phase: Uses pi --print for code review
# 2. Execution phase: Uses GitHub API for issue retrieval and execution
#
# This library orchestrates sub-modules and is sourced by scripts/improve.sh
# ============================================================================

set -euo pipefail

_IMPROVE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required dependencies
source "$_IMPROVE_LIB_DIR/config.sh"
source "$_IMPROVE_LIB_DIR/log.sh"
source "$_IMPROVE_LIB_DIR/github.sh"

# Source improve sub-modules
source "$_IMPROVE_LIB_DIR/improve/deps.sh"
source "$_IMPROVE_LIB_DIR/improve/args.sh"
source "$_IMPROVE_LIB_DIR/improve/env.sh"
source "$_IMPROVE_LIB_DIR/improve/review.sh"
source "$_IMPROVE_LIB_DIR/improve/execution.sh"

# Export DEFAULT_* constants for backward compatibility
# shellcheck disable=SC2034  # Used externally by tests
DEFAULT_MAX_ITERATIONS=$_IMPROVE_DEFAULT_MAX_ITERATIONS
# shellcheck disable=SC2034  # Used externally by tests
DEFAULT_MAX_ISSUES=$_IMPROVE_DEFAULT_MAX_ISSUES
# shellcheck disable=SC2034  # Used externally by tests
DEFAULT_TIMEOUT=$_IMPROVE_DEFAULT_TIMEOUT

# shellcheck disable=SC2034
LOG_DIR=""  # Set in setup_improve_environment after load_config

# ============================================================================
# Main function - Orchestrate continuous improvement workflow
# ============================================================================
improve_main() {
    # Set up trap for cleanup on interruption
    trap cleanup_improve_on_exit EXIT INT TERM
    
    # Parse arguments (sets _PARSE_* global variables)
    parse_improve_arguments "$@"
    
    # Copy to local variables for clarity
    # shellcheck disable=SC2154  # _PARSE_* variables set by parse_improve_arguments
    local max_iterations="$_PARSE_max_iterations"
    # shellcheck disable=SC2154
    local max_issues="$_PARSE_max_issues"
    # shellcheck disable=SC2154
    local timeout="$_PARSE_timeout"
    # shellcheck disable=SC2154
    local iteration="$_PARSE_iteration"
    # shellcheck disable=SC2154
    local log_dir="$_PARSE_log_dir"
    # shellcheck disable=SC2154
    local session_label="$_PARSE_session_label"
    # shellcheck disable=SC2154
    local dry_run="$_PARSE_dry_run"
    # shellcheck disable=SC2154
    local review_only="$_PARSE_review_only"
    # shellcheck disable=SC2154
    local auto_continue="$_PARSE_auto_continue"
    
    # Validate iteration before environment setup (must run in current shell, not subshell)
    validate_improve_iteration "$iteration" "$max_iterations"

    # Setup environment (sets _PARSE_* global variables)
    setup_improve_environment "$iteration" "$max_iterations" "$session_label" "$log_dir" "$dry_run" "$review_only"
    
    # Copy to local variables for clarity
    # shellcheck disable=SC2154  # _PARSE_* variables set by setup_improve_environment
    session_label="$_PARSE_session_label"
    # shellcheck disable=SC2154
    local log_file="$_PARSE_log_file"
    # shellcheck disable=SC2154
    local start_time="$_PARSE_start_time"
    
    # Phase 1: Review
    run_improve_review_phase "$max_issues" "$session_label" "$log_file" "$dry_run" "$review_only"
    
    # Phase 2: Fetch issues
    local created_issues
    created_issues="$(fetch_improve_created_issues "$start_time" "$max_issues" "$session_label")"
    
    # Phase 3: Execute in parallel
    execute_improve_issues_in_parallel "$created_issues"
    
    # Phase 4: Wait for completion
    wait_for_improve_completion "$timeout"
    
    # Phase 5: Next iteration
    start_improve_next_iteration "$iteration" "$max_iterations" "$max_issues" "$timeout" "$log_dir" "$session_label" "$auto_continue"
}
