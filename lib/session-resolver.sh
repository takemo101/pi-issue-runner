#!/usr/bin/env bash
# ============================================================================
# session-resolver.sh - Session name resolution utilities
#
# Provides common helper functions for resolving issue numbers and session
# names from user input. This centralizes the argument parsing pattern used
# across multiple scripts.
#
# Functions:
#   resolve_session_target - Resolves issue number and session name from input
#
# Dependencies:
#   - lib/tmux.sh (mux_generate_session_name, mux_extract_issue_number)
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_SESSION_RESOLVER_SH_SOURCED:-}" ]]; then
    return 0
fi
_SESSION_RESOLVER_SH_SOURCED="true"

# Source dependencies
_SESSION_RESOLVER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SESSION_RESOLVER_LIB_DIR/multiplexer.sh"

# ============================================================================
# resolve_session_target - Resolve issue number and session name from input
#
# Takes either an issue number or session name and returns both values.
# This function encapsulates the common pattern of accepting flexible input
# and resolving it to the canonical issue number and session name pair.
#
# Arguments:
#   $1 - target: Issue number (digits only) or session name
#
# Output:
#   Writes to stdout: "issue_number<TAB>session_name"
#
# Exit codes:
#   0 - Success
#   1 - Invalid input or resolution failed
#
# Examples:
#   # From issue number
#   IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "42")
#   # issue_number="42", session_name="pi-issue-42"
#
#   # From session name
#   IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "pi-issue-42")
#   # issue_number="42", session_name="pi-issue-42"
# ============================================================================
resolve_session_target() {
    local target="$1"
    
    if [[ -z "$target" ]]; then
        echo "Error: target is required" >&2
        return 1
    fi
    
    local issue_number
    local session_name
    
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # Input is an issue number
        issue_number="$target"
        session_name="$(mux_generate_session_name "$issue_number")"
    else
        # Input is a session name
        session_name="$target"
        issue_number="$(mux_extract_issue_number "$session_name")"
    fi
    
    # Output as tab-separated values
    printf "%s\t%s\n" "$issue_number" "$session_name"
    return 0
}
