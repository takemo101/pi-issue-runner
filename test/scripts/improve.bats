#!/usr/bin/env bats
# improve.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプオプションテスト
# ====================

@test "improve.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
}

@test "improve.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "improve.sh --help shows --max-iterations option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--max-iterations"* ]]
}

@test "improve.sh --help shows --max-issues option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--max-issues"* ]]
}

@test "improve.sh --help shows --timeout option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--timeout"* ]]
}

@test "improve.sh --help shows --verbose option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--verbose"* ]]
}

@test "improve.sh --help shows description" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Description:"* ]]
}

@test "improve.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Examples:"* ]]
}

@test "improve.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/improve.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# オプションパーステスト
# ====================

@test "improve.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/improve.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "improve.sh with unexpected argument fails" {
    run "$PROJECT_ROOT/scripts/improve.sh" unexpected-arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

# ====================
# スクリプト構造テスト
# ====================

@test "improve.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/improve.sh"
    [ "$status" -eq 0 ]
}

@test "improve.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has check_dependencies function" {
    grep -q "check_dependencies()" "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# オプション処理テスト
# ====================

@test "improve.sh handles --max-iterations option" {
    grep -q '\-\-max-iterations)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has max_iterations variable" {
    grep -q 'max_iterations=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --max-issues option" {
    grep -q '\-\-max-issues)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --timeout option" {
    grep -q '\-\-timeout)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --iteration option" {
    grep -q '\-\-iteration)' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# デフォルト値テスト
# ====================

@test "improve.sh has DEFAULT_MAX_ITERATIONS" {
    grep -q 'DEFAULT_MAX_ITERATIONS=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has DEFAULT_MAX_ISSUES" {
    grep -q 'DEFAULT_MAX_ISSUES=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has DEFAULT_TIMEOUT" {
    grep -q 'DEFAULT_TIMEOUT=' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# 依存関係チェックテスト
# ====================

@test "improve.sh checks for pi command" {
    grep -q 'pi_command' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh checks for tmux command" {
    grep -q 'command -v tmux' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh reports missing dependencies" {
    grep -q 'Missing dependencies' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# ワークフローテスト
# ====================

@test "improve.sh has phase 1 for reviewing" {
    grep -q 'PHASE 1' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has phase 2 for monitoring" {
    grep -q 'PHASE 2' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has phase 3 for next iteration" {
    grep -q 'PHASE 3' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh uses project-review skill" {
    grep -q 'project-review' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh uses wait-for-sessions.sh" {
    grep -q 'wait-for-sessions.sh' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh shows iteration counter" {
    grep -q 'Iteration' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has recursive exec call" {
    grep -q 'exec "$0"' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh checks max iterations" {
    grep -q 'max_iterations' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# 完了マーカー検出テスト
# ====================

@test "improve.sh defines MARKER_COMPLETE constant" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'MARKER_COMPLETE="###TASK_COMPLETE###"'* ]]
}

@test "improve.sh defines MARKER_NO_ISSUES constant" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'MARKER_NO_ISSUES="###NO_ISSUES###"'* ]]
}

@test "improve.sh has run_pi_with_completion_detection function" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *"run_pi_with_completion_detection()"* ]]
}

@test "run_pi_with_completion_detection uses tee for output" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'tee "$output_file"'* ]]
}

@test "run_pi_with_completion_detection monitors for MARKER_COMPLETE" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'grep -q "$MARKER_COMPLETE"'* ]]
}

@test "run_pi_with_completion_detection monitors for MARKER_NO_ISSUES" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'grep -q "$MARKER_NO_ISSUES"'* ]]
}

@test "run_pi_with_completion_detection cleans up temp file" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'rm -f "$output_file"'* ]]
}

@test "Phase 1 uses run_pi_with_completion_detection" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'run_pi_with_completion_detection "$prompt" "$pi_command"'* ]]
}

# ====================
# セッション待機リトライテスト (Issue #230)
# ====================

@test "improve.sh has DEFAULT_SESSION_WAIT_RETRIES" {
    grep -q 'DEFAULT_SESSION_WAIT_RETRIES=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has DEFAULT_SESSION_WAIT_INTERVAL" {
    grep -q 'DEFAULT_SESSION_WAIT_INTERVAL=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has retry loop for session wait" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'retry_count -lt $DEFAULT_SESSION_WAIT_RETRIES'* ]]
}

@test "improve.sh waits for sessions to start before checking" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'Waiting for sessions to start'* ]]
}

@test "improve.sh logs debug message during session wait" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'log_debug "Waiting for sessions to start'* ]]
}

@test "improve.sh shows wait time in no sessions message" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'No running sessions found after waiting'* ]]
}
