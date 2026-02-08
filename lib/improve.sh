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

# ソースガード（多重読み込み防止）
if [[ -n "${_IMPROVE_SH_SOURCED:-}" ]]; then
    return 0
fi
_IMPROVE_SH_SOURCED="true"

_IMPROVE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_IMPROVE_SCRIPT_DIR="$_IMPROVE_LIB_DIR/../scripts"

# Source required dependencies
source "$_IMPROVE_LIB_DIR/config.sh"
source "$_IMPROVE_LIB_DIR/log.sh"
source "$_IMPROVE_LIB_DIR/github.sh"
source "$_IMPROVE_LIB_DIR/status.sh"
source "$_IMPROVE_LIB_DIR/tmux.sh"
source "$_IMPROVE_LIB_DIR/hooks.sh"

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
    # Parse arguments (sets _PARSE_* global variables)
    parse_improve_arguments "$@"
    
    # Set up trap for cleanup on interruption
    # Note: _IMPROVE_SESSION_LABEL is global to be accessible from trap
    _IMPROVE_SESSION_LABEL="$_PARSE_session_label"
    trap 'cleanup_improve_on_exit "$_IMPROVE_SESSION_LABEL"' EXIT INT TERM
    
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
    
    # Hook: improve開始
    run_hook "on_improve_start" "" "" "" "" "" "" "" \
        "$iteration" "$max_iterations" "" "" "" ""
    
    # Phase 1: Review
    run_improve_review_phase "$max_issues" "$session_label" "$log_file" "$dry_run" "$review_only"
    
    # Phase 2: Fetch issues
    local created_issues
    created_issues="$(fetch_improve_created_issues "$start_time" "$max_issues" "$session_label")"
    
    # Phase 3: Execute in parallel
    execute_improve_issues_in_parallel "$created_issues" "$session_label"
    
    # Phase 4: Wait for completion
    wait_for_improve_completion "$timeout" "$session_label"
    
    # Phase 4.5: Sweep completed sessions
    log_info "Sweeping completed sessions..."
    if ! "$_IMPROVE_SCRIPT_DIR/sweep.sh" --force 2>&1 | grep -v '^$'; then
        log_warn "Sweep encountered issues (non-fatal)"
    fi
    
    # Hook: improve終了（統計収集）
    local total_succeeded=0
    local total_failed=0
    local total_created=0
    
    # Count issues from the current iteration by parsing created_issues
    if [[ -n "$created_issues" ]]; then
        total_created=$(echo "$created_issues" | wc -l | tr -d ' ')
        
        # Count succeeded and failed by checking session status
        while IFS= read -r issue; do
            [[ -z "$issue" ]] && continue
            local status
            status="$(get_status_value "$issue" 2>/dev/null || echo "")"
            if [[ "$status" == "complete" ]]; then
                total_succeeded=$((total_succeeded + 1))
            elif [[ "$status" == "error" ]]; then
                total_failed=$((total_failed + 1))
            fi
        done <<< "$created_issues"
    fi
    
    run_hook "on_improve_end" "" "" "" "" "" "" "" \
        "$iteration" "$max_iterations" \
        "$total_created" "$total_succeeded" "$total_failed" ""
    
    # Phase 5: Next iteration
    start_improve_next_iteration "$iteration" "$max_iterations" "$max_issues" "$timeout" "$log_dir" "$session_label" "$auto_continue"
}
