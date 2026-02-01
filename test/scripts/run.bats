#!/usr/bin/env bats
# run.sh のBatsテスト

load '../test_helper'

setup() {
    # 共通のtmpdirセットアップ
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

@test "run.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "run.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/run.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes all main options" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--branch"* ]]
    [[ "$output" == *"--workflow"* ]]
    [[ "$output" == *"--no-attach"* ]]
    [[ "$output" == *"--force"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "run.sh fails without issue number" {
    run "$PROJECT_ROOT/scripts/run.sh"
    [ "$status" -ne 0 ]
}

@test "run.sh fails with non-numeric issue number" {
    run "$PROJECT_ROOT/scripts/run.sh" abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]]
}

@test "run.sh fails with negative issue number" {
    run "$PROJECT_ROOT/scripts/run.sh" "-42"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]] || [[ "$output" == *"Unknown option"* ]]
}

@test "run.sh fails with decimal issue number" {
    run "$PROJECT_ROOT/scripts/run.sh" "3.14"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]]
}

@test "run.sh fails with mixed alphanumeric issue number" {
    run "$PROJECT_ROOT/scripts/run.sh" "issue-42"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Issue number must be a positive integer"* ]]
}

# ====================
# ワークフロー一覧表示テスト
# ====================

@test "run.sh --list-workflows shows available workflows" {
    run "$PROJECT_ROOT/scripts/run.sh" --list-workflows
    [ "$status" -eq 0 ]
    [[ "$output" == *"default"* ]] || [[ "$output" == *"simple"* ]]
}

# ====================
# オプション解析テスト
# ====================

@test "run.sh accepts --branch option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"-b, --branch"* ]]
}

@test "run.sh accepts --workflow option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"-w, --workflow"* ]]
}

@test "run.sh accepts --base option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--base"* ]]
}

@test "run.sh accepts --no-cleanup option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--no-cleanup"* ]]
}

@test "run.sh accepts --reattach option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--reattach"* ]]
}

@test "run.sh accepts --pi-args option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--pi-args"* ]]
}
