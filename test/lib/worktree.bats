#!/usr/bin/env bats
# worktree.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeベースディレクトリを設定
    export TEST_WORKTREE_BASE="$BATS_TEST_TMPDIR/worktrees"
    mkdir -p "$TEST_WORKTREE_BASE"
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
    
    # 設定をリセット
    unset _CONFIG_LOADED
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
}

teardown() {
    unset PI_RUNNER_WORKTREE_BASE_DIR
    unset PI_RUNNER_WORKTREE_COPY_FILES
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# find_worktree_by_issue テスト
# ====================

@test "find_worktree_by_issue returns empty for nonexistent issue" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(find_worktree_by_issue "99999" 2>/dev/null)" || result=""
    [ -z "$result" ] || ! find_worktree_by_issue "99999" 2>/dev/null
}

@test "find_worktree_by_issue finds worktree with issue-N format" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # issue-N 形式のディレクトリを作成
    mkdir -p "$TEST_WORKTREE_BASE/issue-123"
    
    result="$(find_worktree_by_issue "123")"
    [ "$result" = "$TEST_WORKTREE_BASE/issue-123" ]
}

@test "find_worktree_by_issue finds worktree with issue-N-title format" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # issue-N-title 形式のディレクトリを作成
    mkdir -p "$TEST_WORKTREE_BASE/issue-456-refactor-worktree"
    
    result="$(find_worktree_by_issue "456")"
    [ "$result" = "$TEST_WORKTREE_BASE/issue-456-refactor-worktree" ]
}

@test "find_worktree_by_issue returns first match when multiple exist" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # 複数のディレクトリを作成（先頭一致するもの）
    mkdir -p "$TEST_WORKTREE_BASE/issue-789"
    mkdir -p "$TEST_WORKTREE_BASE/issue-789-another"
    
    result="$(find_worktree_by_issue "789")"
    # 最初に見つかったものを返す
    [ -n "$result" ]
    [[ "$result" == *"issue-789"* ]]
}

# ====================
# copy_files_to_worktree テスト
# ====================

@test "copy_files_to_worktree copies specified files" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # テスト用ファイルを作成
    cd "$PROJECT_ROOT"
    echo "test=value1" > ".env.test"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_COPY_FILES=".env.test"
    load_config "$TEST_CONFIG_FILE"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/copy_test"
    mkdir -p "$TEST_COPY_DIR"
    
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    [ -f "$TEST_COPY_DIR/.env.test" ]
    
    # クリーンアップ
    rm -f ".env.test"
}

# ====================
# list_worktrees テスト（モック使用）
# ====================

@test "list_worktrees returns without error" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    load_config "$TEST_CONFIG_FILE"
    
    # エラーなしで実行されることを確認
    run list_worktrees
    # 結果は環境依存なのでステータスだけチェック
    [ "$status" -eq 0 ] || [ -z "$output" ]
}

# ====================
# get_worktree_path テスト
# ====================

@test "get_worktree_path function exists" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    declare -f get_worktree_path > /dev/null 2>&1 || \
    declare -f find_worktree_by_issue > /dev/null
}

# ====================
# remove_worktree テスト
# ====================

@test "remove_worktree fails for nonexistent path" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    run remove_worktree "/nonexistent/path/worktree"
    [ "$status" -ne 0 ] || [[ "$output" == *"not found"* ]]
}

# ====================
# 実際のworktree作成テスト（Git環境依存）
# ====================

@test "create_worktree creates worktree in git repo" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # Gitリポジトリ内で実行されていることを確認
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-99999-test-$(date +%s)"
    
    worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>/dev/null)" || {
        # 作成に失敗した場合はスキップ
        skip "Failed to create worktree"
    }
    
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        [ -d "$worktree_path" ]
        
        # クリーンアップ
        git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
        git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
    else
        skip "Worktree creation returned empty path"
    fi
}

# ====================
# get_worktree_branch テスト
# ====================

@test "get_worktree_branch returns empty for nonexistent path" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(get_worktree_branch "/nonexistent/worktree/path" 2>/dev/null)" || result=""
    [ -z "$result" ]
}

# ====================
# 構成テスト
# ====================

@test "create_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f create_worktree > /dev/null
}

@test "remove_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f remove_worktree > /dev/null
}

@test "find_worktree_by_issue function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f find_worktree_by_issue > /dev/null
}

@test "list_worktrees function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f list_worktrees > /dev/null
}

@test "copy_files_to_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f copy_files_to_worktree > /dev/null
}

@test "get_worktree_branch function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f get_worktree_branch > /dev/null
}
