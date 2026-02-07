#!/usr/bin/env bash
# ============================================================================
# improve/deps.sh - Dependency checking for improve workflow
#
# Checks for required external commands:
# - pi command
# - gh (GitHub CLI)
# - jq (JSON processor)
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_DEPS_SH_SOURCED:-}" ]]; then
    return 0
fi
_DEPS_SH_SOURCED="true"

# ============================================================================
# Check dependencies for improve workflow
# Returns: 0 if all dependencies are met, 1 otherwise
# ============================================================================
check_improve_dependencies() {
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

# Backward compatibility: keep old function name
check_dependencies() {
    check_improve_dependencies "$@"
}
