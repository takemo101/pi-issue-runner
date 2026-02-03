#!/usr/bin/env bats
# create_worktree.sh のBatsテスト
# Git worktreeを作成するスクリプト

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

@test "create_worktree.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "create_worktree.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "create_worktree.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh"
    [ "$status" -ne 0 ]
}

@test "create_worktree.sh fails with empty branch name" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ""
    [ "$status" -ne 0 ]
}

@test "create_worktree.sh requires branch name argument" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh"
    [[ "$output" == *"branch"* ]] || [[ "$output" == *"required"* ]] || [[ "$output" == *"引数"* ]]
}

# ====================
# Gitリポジトリチェック
# ====================

@test "create_worktree.sh fails outside git repo" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    non_git_dir="$BATS_TEST_TMPDIR/non_git"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "test-branch"
    [ "$status" -ne 0 ]
}

# ====================
# Worktree作成テスト
# ====================

@test "create_worktree.sh creates worktree directory" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "feature-branch"
    [ "$status" -eq 0 ]
    
    # worktreeが作成されたか確認
    [ -d "$TEST_REPO/feature-branch" ] || [ -d "$TEST_REPO/../feature-branch" ]
}

@test "create_worktree.sh outputs created path" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "feature-branch"
    [ "$status" -eq 0 ]
    # パスが出力されること
    [[ "$output" == *"feature-branch"* ]]
}

@test "create_worktree.sh creates branch from base branch" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    # ベースブランチオプションを持つか確認
    grep -q "base\|--base\|-b" "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" 2>/dev/null || \
        skip "base branch option not implemented"
    
    # ベースブランチを作成
    git checkout -b base-branch -q
    
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "new-feature" --base base-branch
    [ "$status" -eq 0 ]
}

@test "create_worktree.sh fails on duplicate worktree" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    # 最初の作成
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "duplicate-branch"
    [ "$status" -eq 0 ]
    
    # 重複作成は失敗するか
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "duplicate-branch"
    [ "$status" -ne 0 ] || [[ "$output" == *"exists"* ]] || [[ "$output" == *"already"* ]]
}

# ====================
# オプションテスト
# ====================

@test "create_worktree.sh supports --force option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    grep -q "force\|--force\|-f" "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" 2>/dev/null || \
        skip "force option not implemented"
    
    # 最初の作成
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "force-test"
    [ "$status" -eq 0 ]
    
    # forceオプションで再作成
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "force-test" --force
    [ "$status" -eq 0 ]
}

@test "create_worktree.sh supports custom directory option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" ]]; then
        skip "create_worktree.sh not found"
    fi
    
    grep -q "dir\|--dir\|-d\|directory" "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" 2>/dev/null || \
        skip "directory option not implemented"
    
    custom_dir="$BATS_TEST_TMPDIR/custom-worktree"
    run "$PROJECT_ROOT/.pi/skills/create-worktree/scripts/create_worktree.sh" "custom-branch" --dir "$custom_dir"
    [ "$status" -eq 0 ]
}
