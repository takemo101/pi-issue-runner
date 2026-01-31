#!/usr/bin/env bats
# attach.sh のBatsテスト

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

@test "attach.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [ "$status" -eq 0 ]
}

@test "attach.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "attach.sh --help shows session-name argument" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "attach.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [[ "$output" == *"Examples:"* ]] || [[ "$output" == *"example"* ]]
}

@test "attach.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/attach.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# エラーケーステスト
# ====================

@test "attach.sh without argument fails" {
    run "$PROJECT_ROOT/scripts/attach.sh"
    [ "$status" -ne 0 ]
}

@test "attach.sh without argument shows error message" {
    run "$PROJECT_ROOT/scripts/attach.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "attach.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/attach.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown"* ]]
}

# ====================
# スクリプト構造テスト
# ====================

@test "attach.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/attach.sh"
    [ "$status" -eq 0 ]
}

@test "attach.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh sources tmux.sh" {
    grep -q "lib/tmux.sh" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh calls generate_session_name" {
    grep -q "generate_session_name" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh calls attach_session" {
    grep -q "attach_session" "$PROJECT_ROOT/scripts/attach.sh"
}

@test "attach.sh handles numeric issue number" {
    grep -q '\[0-9\]' "$PROJECT_ROOT/scripts/attach.sh"
}

# ====================
# セッション名生成テスト
# ====================

@test "generate_session_name contains issue number" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    load_config
    
    result="$(generate_session_name "42")"
    [[ "$result" == *"42"* ]]
}

@test "generate_session_name contains issue pattern" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    load_config
    
    result="$(generate_session_name "42")"
    [[ "$result" == *"issue"* ]]
}
