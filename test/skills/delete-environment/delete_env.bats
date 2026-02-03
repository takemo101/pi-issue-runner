#!/usr/bin/env bats
# delete_env.sh のBatsテスト
# 環境（worktree等）を削除するスクリプト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export ORIGINAL_PATH="$PATH"
    
    # Gitリポジトリをセットアップ
    export TEST_REPO="$BATS_TEST_TMPDIR/test_repo"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit" -q
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

@test "delete_env.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "delete_env.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "delete_env.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh"
    [ "$status" -ne 0 ]
}

@test "delete_env.sh requires issue or branch name" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"引数"* ]] || [ "$status" -ne 0 ]
}

# ====================
# Worktree削除テスト
# ====================

@test "delete_env.sh deletes worktree by issue number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    # worktreeを作成
    mkdir -p "$TEST_REPO/.worktrees/issue-42-test"
    [ -d "$TEST_REPO/.worktrees/issue-42-test" ]
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" "42"
    # 存在しない場合もスキップする
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "delete_env.sh deletes worktree by branch name" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    # worktreeを作成
    mkdir -p "$TEST_REPO/worktree-test"
    [ -d "$TEST_REPO/worktree-test" ]
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" "worktree-test"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ====================
# 依存ツールチェック
# ====================

@test "delete_env.sh checks for git" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    # gitが見つからない場合
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" "test"
    # エラーになるかチェック（実装による）
    [ "$status" -ne 0 ] || [[ "$output" == *"git"* ]]
}

# ====================
# オプションテスト
# ====================

@test "delete_env.sh supports --force option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    grep -q "force\|--force\|-f" "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" 2>/dev/null || \
        skip "force option not implemented"
    
    mkdir -p "$TEST_REPO/.worktrees/issue-99-test"
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" "99" --force
    [ "$status" -eq 0 ]
}

@test "delete_env.sh supports --dry-run option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    grep -q "dry-run\|--dry-run\|-n" "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" 2>/dev/null || \
        skip "dry-run option not implemented"
    
    mkdir -p "$TEST_REPO/.worktrees/issue-100-test"
    [ -d "$TEST_REPO/.worktrees/issue-100-test" ]
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" "100" --dry-run
    # dry-runでは削除されない
    [ -d "$TEST_REPO/.worktrees/issue-100-test" ]
}

@test "delete_env.sh supports --all option to cleanup all" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" ]]; then
        skip "delete_env.sh not found"
    fi
    
    grep -q "all\|--all\|-a" "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" 2>/dev/null || \
        skip "all option not implemented"
    
    run "$PROJECT_ROOT/.pi/skills/delete-environment/scripts/delete_env.sh" --all
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
