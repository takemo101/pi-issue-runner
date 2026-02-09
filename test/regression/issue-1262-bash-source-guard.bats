#!/usr/bin/env bats
# test/regression/issue-1262-bash-source-guard.bats
# Regression test: scripts/cleanup.sh can be sourced without side effects

load '../test_helper'

@test "Issue #1262: cleanup.sh can be sourced without executing main" {
    # Source cleanup.sh and verify functions are available without side effects
    run bash -c '
        source "'"$PROJECT_ROOT"'/scripts/cleanup.sh"
        # If main ran, it would fail or produce errors since no config exists
        # Verify key functions are available
        type parse_cleanup_arguments >/dev/null 2>&1 || exit 1
        type execute_single_cleanup >/dev/null 2>&1 || exit 1
        type execute_all_cleanup >/dev/null 2>&1 || exit 1
        type usage >/dev/null 2>&1 || exit 1
        type main >/dev/null 2>&1 || exit 1
        echo "OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "Issue #1262: cleanup.sh BASH_SOURCE guard is present" {
    grep -q 'BASH_SOURCE\[0\].*==.*\${0}' "$PROJECT_ROOT/scripts/cleanup.sh"
}
