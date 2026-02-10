#!/usr/bin/env bats
# test/lib/step-runner.bats - step-runner.sh のテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    export PI_ISSUE_NUMBER="42"
    export PI_BRANCH_NAME="feature/test"
    export PI_WORKTREE_PATH="$BATS_TEST_TMPDIR"

    source "$PROJECT_ROOT/lib/step-runner.sh"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR"
}

# ===================
# expand_step_variables
# ===================

@test "expand_step_variables replaces issue_number" {
    result=$(expand_step_variables 'gh issue view ${issue_number}' "42")
    [[ "$result" == "gh issue view 42" ]]
}

@test "expand_step_variables replaces pr_number" {
    result=$(expand_step_variables 'gh pr checks ${pr_number}' "" "99")
    [[ "$result" == "gh pr checks 99" ]]
}

@test "expand_step_variables replaces branch_name" {
    result=$(expand_step_variables 'git checkout ${branch_name}' "" "" "feature/test")
    [[ "$result" == "git checkout feature/test" ]]
}

@test "expand_step_variables replaces worktree_path" {
    result=$(expand_step_variables 'cd ${worktree_path}' "" "" "" "/tmp/wt")
    [[ "$result" == "cd /tmp/wt" ]]
}

@test "expand_step_variables replaces multiple variables" {
    result=$(expand_step_variables 'echo ${issue_number} ${branch_name}' "42" "" "main")
    [[ "$result" == "echo 42 main" ]]
}

@test "expand_step_variables uses env vars as defaults" {
    result=$(expand_step_variables 'echo ${issue_number}')
    [[ "$result" == "echo 42" ]]
}

# ===================
# run_command_step
# ===================

@test "run_command_step succeeds with exit 0 command" {
    run run_command_step "echo hello" 10 "$BATS_TEST_TMPDIR" "42" "" "main"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello"* ]]
}

@test "run_command_step fails with exit 1 command" {
    run run_command_step "exit 1" 10 "$BATS_TEST_TMPDIR" "42" "" "main"
    [[ "$status" -ne 0 ]]
}

@test "run_command_step captures stdout and stderr" {
    run run_command_step "echo out && echo err >&2" 10 "$BATS_TEST_TMPDIR" "42" "" "main"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"out"* ]]
    [[ "$output" == *"err"* ]]
}

@test "run_command_step runs in worktree directory" {
    mkdir -p "$BATS_TEST_TMPDIR/subdir"
    run run_command_step "pwd" 10 "$BATS_TEST_TMPDIR/subdir" "42" "" "main"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"subdir"* ]]
}

@test "run_command_step sets PI_ISSUE_NUMBER env var" {
    run run_command_step 'echo $PI_ISSUE_NUMBER' 10 "$BATS_TEST_TMPDIR" "99" "" "main"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"99"* ]]
}

@test "run_command_step expands template variables" {
    run run_command_step 'echo ${issue_number}' 10 "$BATS_TEST_TMPDIR" "42" "" "main"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"42"* ]]
}

@test "run_command_step times out long-running command" {
    run run_command_step "sleep 60" 1 "$BATS_TEST_TMPDIR" "42" "" "main"
    [[ "$status" -ne 0 ]]
}
