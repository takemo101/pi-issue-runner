#!/usr/bin/env bash
# ============================================================================
# improve/env.sh - Environment setup for improve workflow
#
# Handles environment initialization, validation, and session label generation.
# ============================================================================

set -euo pipefail

# ============================================================================
# Validate iteration number against maximum
# Arguments: $1=current iteration, $2=max iterations
# Exits: 0 if max iterations reached (normal completion)
# ============================================================================
validate_improve_iteration() {
    local iteration="$1"
    local max_iterations="$2"
    
    if [[ $iteration -gt $max_iterations ]]; then
        echo "" >&2
        echo "🏁 Maximum iterations ($max_iterations) reached" >&2
        exit 0
    fi
}

# ============================================================================
# Generate a unique session label for this improve run
# Output: Session label string (e.g., "pi-runner-20260205-223000")
# ============================================================================
generate_improve_session_label() {
    echo "pi-runner-$(date +%Y%m%d-%H%M%S)"
}

# ============================================================================
# Setup environment and validate configuration
# Arguments: $1=iteration, $2=max_iterations, $3=session_label, $4=log_dir,
#            $5=dry_run, $6=review_only
# Output: Sets global variables with _PARSE_ prefix
# ============================================================================
setup_improve_environment() {
    local iteration="$1"
    local max_iterations="$2"
    local session_label="$3"
    local log_dir="$4"
    local dry_run="$5"
    local review_only="$6"

    load_config
    check_improve_dependencies || exit 1

    # If log_dir is empty, get from config
    if [[ -z "$log_dir" ]]; then
        log_dir="$(get_config improve_logs_dir)"
    fi

    # Note: validate_improve_iteration is called before this function
    # in improve_main() to avoid subshell exit issues

    # Generate session label if not provided
    if [[ -z "$session_label" ]]; then
        session_label="$(generate_improve_session_label)"
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

    # Display header (to stderr)
    {
        echo ""
        echo "=== Continuous Improvement - Iteration $iteration/$max_iterations ==="
        echo ""
        echo "Session label: $session_label"
        echo "Log file: $log_file"
        echo ""
    } >&2

    # Set global variables (no escaping needed - direct assignment is safe)
    _PARSE_session_label="$session_label"
    _PARSE_log_file="$log_file"
    _PARSE_start_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
