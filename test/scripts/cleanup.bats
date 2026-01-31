#!/usr/bin/env bats
# cleanup.sh のBatsテスト

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

@test "cleanup.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "cleanup.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "cleanup.sh requires issue number" {
    run "$PROJECT_ROOT/scripts/cleanup.sh"
    [ "$status" -ne 0 ]
}

# ====================
# オプションテスト
# ====================

@test "cleanup.sh accepts --force option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--force"* ]] || [[ "$output" == *"-f"* ]]
}

@test "cleanup.sh accepts --delete-branch option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--delete-branch"* ]]
}

@test "cleanup.sh accepts --keep-session option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--keep-session"* ]]
}

@test "cleanup.sh accepts --keep-worktree option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--keep-worktree"* ]]
}
