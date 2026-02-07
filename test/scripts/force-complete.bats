#!/usr/bin/env bats
# force-complete.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # テストではtmuxを使用
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    unset _CONFIG_LOADED
    unset _MUX_TYPE
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

@test "force-complete.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [ "$status" -eq 0 ]
}

@test "force-complete.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "force-complete.sh --help shows session-name argument" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "force-complete.sh --help shows --error option" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [[ "$output" == *"--error"* ]]
}

@test "force-complete.sh --help shows --message option" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [[ "$output" == *"--message"* ]]
}

@test "force-complete.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [[ "$output" == *"Examples:"* ]]
}

@test "force-complete.sh --help shows pi-issue-42 example" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --help
    [[ "$output" == *"pi-issue-42"* ]] || [[ "$output" == *"42"* ]]
}

@test "force-complete.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# エラーケーステスト
# ====================

@test "force-complete.sh without argument fails" {
    run "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -ne 0 ]
}

@test "force-complete.sh without argument shows error message" {
    run "$PROJECT_ROOT/scripts/force-complete.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "force-complete.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "force-complete.sh with --message but no value fails" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" 42 --message
    [ "$status" -ne 0 ]
}

# ====================
# スクリプト構造テスト
# ====================

@test "force-complete.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -eq 0 ]
}

@test "force-complete.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh sources tmux.sh" {
    grep -q "lib/tmux.sh" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh sources session-resolver.sh" {
    grep -q "session-resolver.sh" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh uses resolve_session_target" {
    grep -q "resolve_session_target" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh calls session_exists" {
    grep -q "session_exists" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh sends completion marker" {
    grep -q "TASK_COMPLETE" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh sends error marker" {
    grep -q "TASK_ERROR" "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh uses send_keys function" {
    grep -q "send_keys" "$PROJECT_ROOT/scripts/force-complete.sh"
}

# ====================
# オプション処理テスト
# ====================

@test "force-complete.sh has --error flag handling" {
    grep -q '\-\-error' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh has --message flag handling" {
    grep -q '\-\-message' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh completion marker format is correct" {
    grep -q 'TASK_COMPLETE_.*issue_number' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh error marker format is correct" {
    grep -q 'TASK_ERROR_.*issue_number' "$PROJECT_ROOT/scripts/force-complete.sh"
}
