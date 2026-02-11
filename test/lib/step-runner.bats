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

# ===================
# sanitize_filename
# ===================

@test "sanitize_filename converts spaces to hyphens" {
    result="$(sanitize_filename "ShellCheck 静的解析")"
    [[ "$result" == "ShellCheck-静的解析" ]]
}

@test "sanitize_filename removes unsafe characters" {
    result="$(sanitize_filename "test/foo:bar")"
    [[ "$result" == "test-foobar" ]]
}

@test "sanitize_filename collapses multiple hyphens" {
    result="$(sanitize_filename "a  /  b")"
    [[ "$result" == "a-b" ]]
}

# ===================
# save_run_output
# ===================

@test "save_run_output creates output file with metadata header" {
    local output_path
    output_path="$(save_run_output "$BATS_TEST_TMPDIR" "test step" "echo hello" 0 "hello")"
    [[ "$output_path" == ".pi/run-outputs/test-step.log" ]]
    [[ -f "$BATS_TEST_TMPDIR/.pi/run-outputs/test-step.log" ]]
    local content
    content="$(cat "$BATS_TEST_TMPDIR/.pi/run-outputs/test-step.log")"
    [[ "$content" == *"# Step: test step"* ]]
    [[ "$content" == *"# Command: echo hello"* ]]
    [[ "$content" == *"# Exit Code: 0"* ]]
    [[ "$content" == *"hello"* ]]
}

@test "save_run_output truncates large output" {
    # Generate output larger than 100KB
    local large_output
    large_output="$(head -c 200000 /dev/urandom | base64)"
    _RUN_OUTPUT_MAX_SIZE=1024
    local output_path
    output_path="$(save_run_output "$BATS_TEST_TMPDIR" "large" "cat big" 0 "$large_output")"
    local file_size
    file_size=$(wc -c < "$BATS_TEST_TMPDIR/.pi/run-outputs/large.log" | tr -d ' ')
    # Should be around 1024 + truncation header
    [[ "$file_size" -lt 2048 ]]
    local content
    content="$(cat "$BATS_TEST_TMPDIR/.pi/run-outputs/large.log")"
    [[ "$content" == *"truncated"* ]]
}

@test "run_command_step saves output to file" {
    run_command_step "echo test-output" 10 "$BATS_TEST_TMPDIR" "42" "" "main" "My Test"
    [[ -f "$BATS_TEST_TMPDIR/.pi/run-outputs/My-Test.log" ]]
    local content
    content="$(cat "$BATS_TEST_TMPDIR/.pi/run-outputs/My-Test.log")"
    [[ "$content" == *"test-output"* ]]
    [[ "$content" == *"# Exit Code: 0"* ]]
}

@test "run_command_step saves output on failure too" {
    run_command_step "echo fail-output && exit 1" 10 "$BATS_TEST_TMPDIR" "42" "" "main" "Failing Step" || true
    [[ -f "$BATS_TEST_TMPDIR/.pi/run-outputs/Failing-Step.log" ]]
    local content
    content="$(cat "$BATS_TEST_TMPDIR/.pi/run-outputs/Failing-Step.log")"
    [[ "$content" == *"fail-output"* ]]
    [[ "$content" == *"# Exit Code: 1"* ]]
}
