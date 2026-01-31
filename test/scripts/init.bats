#!/usr/bin/env bats
# init.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # テスト用のGitリポジトリを作成
    export TEST_REPO_DIR="${BATS_TEST_TMPDIR}/test-repo"
    mkdir -p "$TEST_REPO_DIR"
    (cd "$TEST_REPO_DIR" && git init --quiet)
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

@test "init.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/init.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "init.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/init.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes --full option" {
    run "$PROJECT_ROOT/scripts/init.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--full"* ]]
}

@test "help includes --minimal option" {
    run "$PROJECT_ROOT/scripts/init.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--minimal"* ]]
}

@test "help includes --force option" {
    run "$PROJECT_ROOT/scripts/init.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--force"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/init.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "init.sh fails with unknown option" {
    cd "$TEST_REPO_DIR"
    run "$PROJECT_ROOT/scripts/init.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "init.sh fails with unexpected argument" {
    cd "$TEST_REPO_DIR"
    run "$PROJECT_ROOT/scripts/init.sh" some-argument
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

# ====================
# Gitリポジトリチェックテスト
# ====================

@test "init.sh fails outside git repository" {
    # 一時ディレクトリに移動（Gitリポジトリではない）
    cd "$BATS_TEST_TMPDIR"
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Git リポジトリではありません"* ]] || [[ "$output" == *"git init"* ]]
}

# ====================
# 初期化実行テスト
# ====================

@test "init.sh creates .pi-runner.yaml in git repository" {
    cd "$TEST_REPO_DIR"
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [ -f "$TEST_REPO_DIR/.pi-runner.yaml" ]
}

@test "init.sh --minimal creates only config file" {
    cd "$TEST_REPO_DIR"
    run "$PROJECT_ROOT/scripts/init.sh" --minimal
    [ "$status" -eq 0 ]
    [ -f "$TEST_REPO_DIR/.pi-runner.yaml" ]
    [[ "$output" == *"最小初期化完了"* ]]
}

@test "init.sh --full creates agents and workflows directories" {
    cd "$TEST_REPO_DIR"
    run "$PROJECT_ROOT/scripts/init.sh" --full
    [ "$status" -eq 0 ]
    [ -f "$TEST_REPO_DIR/agents/custom.md" ]
    [ -f "$TEST_REPO_DIR/workflows/custom.yaml" ]
}

@test "init.sh --force overwrites existing files" {
    cd "$TEST_REPO_DIR"
    # 最初に作成
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    # 再度実行（--force付き）
    run "$PROJECT_ROOT/scripts/init.sh" --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"上書き"* ]]
}

@test "init.sh without --force skips existing files" {
    cd "$TEST_REPO_DIR"
    # 最初に作成
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    # 再度実行（--forceなし）
    run "$PROJECT_ROOT/scripts/init.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"既に存在"* ]]
}
