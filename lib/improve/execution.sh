#!/usr/bin/env bash
# ============================================================================
# improve/execution.sh - Execution and monitoring for improve workflow
#
# Handles:
# - Fetching created Issues
# - Starting parallel execution
# - Waiting for completion
# - Starting next iteration
# - Cleanup on exit
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_EXECUTION_SH_SOURCED:-}" ]]; then
    return 0
fi
_EXECUTION_SH_SOURCED="true"

# Define script directory explicitly from this file's location
# Note: Previously used ${SCRIPT_DIR:-...} fallback, but this could use
# unexpected values if SCRIPT_DIR was set elsewhere. Now always compute
# from this file's actual location for safety.
_IMPROVE_EXEC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"

# ============================================================================
# File-based session tracking helpers (Issue #1106)
# ============================================================================

# Get active issues for the current improve session
# Uses session_label to filter only issues started by this improve iteration
# Arguments: $1=session_label
# Output: Issue numbers (one per line)
get_improve_active_issues() {
    local session_label="${1:-}"
    
    if [[ -z "$session_label" ]]; then
        # No label - return all running issues
        list_issues_by_status "running" 2>/dev/null || true
    else
        # Filter by label
        list_issues_by_status_and_label "running" "$session_label" 2>/dev/null || true
    fi
}

# Count active sessions for the current improve iteration
# Arguments: $1=session_label
# Output: Number of active sessions
count_improve_active_sessions() {
    local session_label="${1:-}"
    local count=0
    
    while IFS= read -r _; do
        count=$((count + 1))
    done < <(get_improve_active_issues "$session_label")
    
    echo "$count"
}

# ============================================================================
# Cleanup function for EXIT trap
# Arguments: $1=session_label (from improve.sh)
# ============================================================================
cleanup_improve_on_exit() {
    local exit_code=$?
    local session_label="${1:-}"
    
    # Get active issues for this improve session
    local active_issues=()
    while IFS= read -r issue; do
        [[ -n "$issue" ]] && active_issues+=("$issue")
    done < <(get_improve_active_issues "$session_label")
    
    # Only cleanup if there are active sessions and exit is not normal
    if [[ ${#active_issues[@]} -gt 0 && $exit_code -ne 0 ]]; then
        log_warn "Interrupted! Cleaning up ${#active_issues[@]} active session(s)..."
        for issue in "${active_issues[@]}"; do
            log_info "  Cleaning up Issue #$issue..."
            "${_IMPROVE_EXEC_SCRIPT_DIR}/cleanup.sh" "pi-issue-$issue" --force 2>/dev/null || true
        done
        log_info "Cleanup completed."
    fi
    
    exit $exit_code
}

# ============================================================================
# Fetch issues created during review phase
# Arguments: $1=start_time, $2=max_issues, $3=session_label
# Output: Issue numbers (one per line) to stdout
# Note: All log messages go to stderr to prevent pollution of output
# ============================================================================
fetch_improve_created_issues() {
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
# Wait for a session slot to become available
# Polls active sessions until at least one completes or concurrent limit allows
# Arguments: $1=check_interval (default: 10), $2=session_label
# ============================================================================
_wait_for_available_slot() {
    local interval="${1:-10}"
    local session_label="${2:-}"
    local max_concurrent
    max_concurrent="$(get_config parallel_max_concurrent)"
    
    # No limit configured
    if [[ -z "$max_concurrent" || "$max_concurrent" == "0" ]]; then
        return 0
    fi
    
    while true; do
        local current_count
        current_count="$(count_improve_active_sessions "$session_label")"
        if [[ "$current_count" -lt "$max_concurrent" ]]; then
            return 0
        fi
        echo "  Concurrent limit ($max_concurrent) reached ($current_count active). Waiting ${interval}s for a slot..."
        sleep "$interval"
        
        # Cleanup completed sessions that are still lingering
        while IFS= read -r issue_num; do
            local status
            status="$(get_status_value "$issue_num" 2>/dev/null || echo "")"
            if [[ "$status" == "complete" || "$status" == "error" ]]; then
                # Cleanup the session if it's still lingering
                local session_name
                session_name="$(generate_session_name "$issue_num")"
                if mux_session_exists "$session_name" 2>/dev/null; then
                    log_info "Cleaning up completed session: $session_name (status: $status)"
                    "${_IMPROVE_EXEC_SCRIPT_DIR}/cleanup.sh" "$session_name" --force 2>/dev/null || true
                fi
            fi
        done < <(get_improve_active_issues "$session_label")
    done
}

# ============================================================================
# Start parallel execution of issues
# Arguments: $1=newline-separated issue numbers, $2=session_label
# ============================================================================
execute_improve_issues_in_parallel() {
    local issues="$1"
    local session_label="${2:-}"
    
    echo ""
    echo "[PHASE 3] Starting parallel execution..."
    
    # Hook: イテレーション開始
    if declare -f run_hook &>/dev/null; then
        run_hook "on_iteration_start" "" "" "" "" "" "" "" \
            "${_IMPROVE_ITERATION:-1}" "${_IMPROVE_MAX_ITERATIONS:-1}" "" "" "" ""
    fi
    
    if [[ -z "$issues" ]]; then
        echo "  No issues to execute"
        return 0
    fi
    
    while IFS= read -r issue; do
        [[ -z "$issue" ]] && continue
        
        # Wait for an available slot before starting
        _wait_for_available_slot 10 "$session_label"
        
        echo "  Starting Issue #$issue..."
        # Build run.sh arguments with label
        local run_args=("$issue" "--no-attach")
        if [[ -n "$session_label" ]]; then
            run_args+=("--label" "$session_label")
        fi
        
        if "${_IMPROVE_EXEC_SCRIPT_DIR}/run.sh" "${run_args[@]}"; then
            # Session started successfully (status saved by run.sh)
            :
        else
            log_warn "Failed to start session for Issue #$issue"
        fi
    done <<< "$issues"
}

# ============================================================================
# Wait for all sessions to complete
# Arguments: $1=timeout, $2=session_label
# ============================================================================
wait_for_improve_completion() {
    local timeout="$1"
    local session_label="${2:-}"

    echo ""
    echo "[PHASE 4] Waiting for sessions to complete..."
    
    # Get active issues from status files
    local active_issues=()
    while IFS= read -r issue; do
        [[ -n "$issue" ]] && active_issues+=("$issue")
    done < <(get_improve_active_issues "$session_label")
    
    if [[ ${#active_issues[@]} -eq 0 ]]; then
        echo "  No active sessions to wait for"
        return 0
    fi
    
    echo "  Waiting for: ${active_issues[*]}"
    
    if ! "${_IMPROVE_EXEC_SCRIPT_DIR}/wait-for-sessions.sh" "${active_issues[@]}" --timeout "$timeout" --cleanup; then
        log_warn "Some sessions failed or timed out"
    fi
    
    # Hook: イテレーション終了（統計収集）
    local succeeded=0
    local failed=0
    local created=${#active_issues[@]}
    
    # セッション状態から成功/失敗を集計
    for issue in "${active_issues[@]}"; do
        local status
        status="$(get_status_value "$issue" 2>/dev/null || echo "")"
        if [[ "$status" == "complete" ]]; then
            succeeded=$((succeeded + 1))
        elif [[ "$status" == "error" ]]; then
            failed=$((failed + 1))
        fi
    done
    
    if declare -f run_hook &>/dev/null; then
        run_hook "on_iteration_end" "" "" "" "" "" "" "" \
            "${_IMPROVE_ITERATION:-1}" "${_IMPROVE_MAX_ITERATIONS:-1}" \
            "$created" "$succeeded" "$failed" ""
    fi
}

# ============================================================================
# Start next iteration with updated parameters
# Arguments: $1=iteration, $2=max_iterations, $3=max_issues, $4=timeout,
#            $5=log_dir, $6=session_label, $7=auto_continue
# ============================================================================
start_improve_next_iteration() {
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

# Backward compatibility: keep old function names
cleanup_on_exit() {
    cleanup_improve_on_exit "$@"
}

fetch_created_issues() {
    fetch_improve_created_issues "$@"
}

execute_issues_in_parallel() {
    execute_improve_issues_in_parallel "$@"
}

wait_for_completion() {
    wait_for_improve_completion "$@"
}

start_next_iteration() {
    start_improve_next_iteration "$@"
}
