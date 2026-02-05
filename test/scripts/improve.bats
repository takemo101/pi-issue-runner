#!/usr/bin/env bats
# improve.sh のBatsテスト (2段階方式)

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

@test "improve.sh --help shows --log-dir option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--log-dir"* ]]
}

@test "improve.sh --help shows --dry-run option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--dry-run"* ]]
}

@test "improve.sh --help shows --review-only option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--review-only"* ]]
}

@test "improve.sh --help shows --auto-continue option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--auto-continue"* ]]
}

@test "improve.sh --help shows --label option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--label"* ]]
}

@test "improve.sh --help shows description" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Description:"* ]]
}

@test "improve.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Examples:"* ]]
}

@test "improve.sh --help shows log file information" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Log files:"* ]]
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

@test "improve.sh sources lib/improve.sh" {
    grep -q "lib/improve.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh calls improve_main function" {
    grep -q "improve_main" "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# CLI機能テスト（実装はlib/improve.shにある）
# ====================

@test "improve.sh can be executed" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
}

# ====================
# Note: Implementation details have been moved to lib/improve.sh
# and are tested in test/lib/improve.bats
# ====================
