#!/usr/bin/env bats
# test/scripts/next.bats - Tests for scripts/next.sh

load '../test_helper'

setup() {
    # 各テストで独立したtmpdirを作成
    export BATS_TEST_TMPDIR="$(mktemp -d)"
    export TEST_CONFIG_FILE="$BATS_TEST_TMPDIR/.pi-runner.yaml"
    
    # デフォルト設定ファイル作成（正しいYAML階層構造）
    cat > "$TEST_CONFIG_FILE" <<CFGEOF
worktree:
  base_dir: "${BATS_TEST_TMPDIR}/.worktrees"
pi:
  command: "echo pi"
default_branch: "main"
CFGEOF
    
    # ステータスディレクトリ作成
    mkdir -p "$BATS_TEST_TMPDIR/.worktrees/.status"
    
    # テスト用モック（test_helper.bashと互換性を持たせる）
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    mock_gh
    mock_git
    enable_mocks
}

teardown() {
    # PATHを復元
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    # tmpdirをクリーンアップ
    if [[ -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "next.sh: --help shows usage" {
    run "$PROJECT_ROOT/scripts/next.sh" --help
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Options:"* ]]
    [[ "$output" == *"--count"* ]]
    [[ "$output" == *"--json"* ]]
}

@test "next.sh: -h shows usage" {
    run "$PROJECT_ROOT/scripts/next.sh" -h
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "next.sh: invalid option shows error" {
    run "$PROJECT_ROOT/scripts/next.sh" --invalid-option
    
    [ "$status" -eq 3 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "next.sh: --count without argument shows error" {
    run "$PROJECT_ROOT/scripts/next.sh" --count
    
    [ "$status" -eq 3 ]
    [[ "$output" == *"requires an argument"* ]]
}

@test "next.sh: --count with non-numeric value shows error" {
    run "$PROJECT_ROOT/scripts/next.sh" --count abc
    
    [ "$status" -eq 3 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "next.sh: --count with zero shows error" {
    run "$PROJECT_ROOT/scripts/next.sh" --count 0
    
    [ "$status" -eq 3 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "next.sh: --label without argument shows error" {
    run "$PROJECT_ROOT/scripts/next.sh" --label
    
    [ "$status" -eq 3 ]
    [[ "$output" == *"requires an argument"* ]]
}
