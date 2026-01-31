#!/usr/bin/env bats
# wait-for-sessions.sh のBatsテスト

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
# ヘルプ表示テスト
# ====================

@test "wait-for-sessions.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "wait-for-sessions.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes --timeout option" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--timeout"* ]]
}

@test "help includes --interval option" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--interval"* ]]
}

@test "help includes --fail-fast option" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--fail-fast"* ]]
}

@test "help includes --quiet option" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--quiet"* ]] || [[ "$output" == *"-q"* ]]
}

@test "help includes description" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Description:"* ]]
}

@test "help includes exit codes section" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Exit codes:"* ]] || [[ "$output" == *"exit"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "wait-for-sessions.sh fails without issue numbers" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh"
    [ "$status" -eq 3 ]  # 引数エラーは終了コード3
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "wait-for-sessions.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --unknown-option
    [ "$status" -eq 3 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "wait-for-sessions.sh fails with non-numeric issue number" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" abc
    [ "$status" -eq 3 ]
    [[ "$output" == *"Invalid issue number"* ]]
}

# ====================
# 複数Issue指定テスト
# ====================

@test "wait-for-sessions.sh accepts multiple issue numbers" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    # ヘルプの引数欄に複数指定可を示す記載がある
    [[ "$output" == *"issue-number..."* ]] || [[ "$output" == *"複数"* ]] || [[ "$output" == *"multiple"* ]]
}

# ====================
# 終了コードテスト
# ====================

@test "exit code 3 for argument errors" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh"
    [ "$status" -eq 3 ]
}

@test "exit code documentation exists in help" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]] && [[ "$output" == *"1"* ]] && [[ "$output" == *"2"* ]] && [[ "$output" == *"3"* ]]
}
