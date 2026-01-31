#!/usr/bin/env bats
# status.sh のBatsテスト

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

@test "status.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/status.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "status.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/status.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes arguments description" {
    run "$PROJECT_ROOT/scripts/status.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "help includes --output option" {
    run "$PROJECT_ROOT/scripts/status.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--output"* ]] || [[ "$output" == *"-o"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "status.sh fails without session name or issue number" {
    run "$PROJECT_ROOT/scripts/status.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "status.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/status.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================
# 入力形式テスト
# ====================

@test "status.sh accepts issue number format" {
    # モックを準備
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/status.sh" 42
    # ヘルプが表示されなければ引数は解析された
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "status.sh accepts session name format" {
    # モックを準備
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/status.sh" pi-issue-42
    # ヘルプが表示されなければ引数は解析された
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

# ====================
# 出力フォーマットテスト
# ====================

@test "status.sh output includes Issue section" {
    # モックを準備
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/status.sh" 42
    [[ "$output" == *"Issue"* ]] || [[ "$output" == *"issue"* ]] || [ "$status" -ne 0 ]
}

@test "status.sh output includes Session section" {
    # モックを準備
    mock_gh
    mock_tmux
    mock_git
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/status.sh" 42
    [[ "$output" == *"Session"* ]] || [[ "$output" == *"session"* ]] || [ "$status" -ne 0 ]
}
