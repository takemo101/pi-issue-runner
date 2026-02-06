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
    
    # Parse arguments
    # shellcheck disable=SC2034  # Variables set by eval
    eval "$(parse_improve_arguments "$@")"
    
    # Validate iteration before environment setup (must run in current shell, not subshell)
    # shellcheck disable=SC2154  # Variables set by eval above
    validate_improve_iteration "$iteration" "$max_iterations"

    # Setup environment
    # shellcheck disable=SC2034  # Variables set by eval
    # shellcheck disable=SC2154  # Variables set by eval above
    eval "$(setup_improve_environment "$iteration" "$max_iterations" "$session_label" "$log_dir" "$dry_run" "$review_only")"
    
    # Phase 1: Review
    # shellcheck disable=SC2154  # Variables set by eval above
    run_improve_review_phase "$max_issues" "$session_label" "$log_file" "$dry_run" "$review_only"
    
    # Phase 2: Fetch issues
    local created_issues
    # shellcheck disable=SC2154  # start_time set by eval above
    created_issues="$(fetch_improve_created_issues "$start_time" "$max_issues" "$session_label")"
    
    # Phase 3: Execute in parallel
    execute_improve_issues_in_parallel "$created_issues"
    
    # Phase 4: Wait for completion
    # shellcheck disable=SC2154  # timeout set by eval above
    wait_for_improve_completion "$timeout"
    
    # Phase 5: Next iteration
    # shellcheck disable=SC2154  # auto_continue set by eval above
    start_improve_next_iteration "$iteration" "$max_iterations" "$max_issues" "$timeout" "$log_dir" "$session_label" "$auto_continue"
}
