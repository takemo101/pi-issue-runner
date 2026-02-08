#!/usr/bin/env bats
# Regression test for Issue #1129
# start_agent_session must receive session_label as an explicit argument,
# not rely on implicit variable scoping from the caller.

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "start_agent_session accepts session_label as 10th argument" {
    # Verify the function signature includes session_label as ${10}
    run grep -n 'local session_label="\${10:-}"' "$PROJECT_ROOT/scripts/run.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'local session_label="${10:-}"'* ]]
}

@test "start_agent_session call site passes session_label as argument" {
    # Verify the call site passes session_label as the 10th argument
    run grep -n 'start_agent_session.*\$session_label' "$PROJECT_ROOT/scripts/run.sh"
    [ "$status" -eq 0 ]
    # Should find the call with "$session_label" as the last argument
    [[ "$output" == *'"$session_label"'* ]]
}

@test "start_agent_session function comment documents session_label" {
    # Verify the function comment includes $10=session_label
    run grep -A5 'Subfunction: start_agent_session' "$PROJECT_ROOT/scripts/run.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'$10=session_label'* ]]
}
