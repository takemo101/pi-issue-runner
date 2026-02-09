#!/usr/bin/env bats
# Regression test for Issue #1280
# echo "$var" mishandles inputs starting with -n, -e, -E
# Fixed by using printf '%s\n' instead of echo

load '../test_helper'

setup() {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/ci-classifier.sh"
}

# has_dangerous_patterns: inputs starting with echo flags

@test "regression #1280: has_dangerous_patterns detects dangerous pattern in -n prefixed input" {
    run has_dangerous_patterns '-n $(rm -rf /)'
    [ "$status" -eq 0 ]
}

@test "regression #1280: has_dangerous_patterns detects dangerous pattern in -e prefixed input" {
    run has_dangerous_patterns '-e $(whoami)'
    [ "$status" -eq 0 ]
}

@test "regression #1280: has_dangerous_patterns detects dangerous pattern in -E prefixed input" {
    run has_dangerous_patterns '-E ${PATH}'
    [ "$status" -eq 0 ]
}

@test "regression #1280: has_dangerous_patterns detects backtick in -n prefixed input" {
    run has_dangerous_patterns '-n `id`'
    [ "$status" -eq 0 ]
}

# classify_ci_failure: inputs starting with echo flags

@test "regression #1280: classify_ci_failure classifies -n prefixed format error" {
    run classify_ci_failure '-n Diff in src/main.rs'
    [ "$status" -eq 0 ]
    [ "$output" = "format" ]
}

@test "regression #1280: classify_ci_failure classifies -e prefixed build error" {
    run classify_ci_failure '-e error[E0308]: expected bool, found i32'
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "regression #1280: classify_ci_failure classifies -E prefixed test failure" {
    run classify_ci_failure '-E not ok 1 some test'
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}
