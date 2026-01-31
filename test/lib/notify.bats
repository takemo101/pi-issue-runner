#!/usr/bin/env bats
# notify.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeディレクトリを設定
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/notify.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # ログを抑制
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# get_status_dir テスト
# ====================

@test "get_status_dir returns correct path" {
    result="$(get_status_dir)"
    [ "$result" = "$TEST_WORKTREE_DIR/.status" ]
}

# ====================
# init_status_dir テスト
# ====================

@test "init_status_dir creates directory" {
    rm -rf "$TEST_WORKTREE_DIR/.status"
    init_status_dir
    [ -d "$TEST_WORKTREE_DIR/.status" ]
}

# ====================
# save_status テスト
# ====================

@test "save_status creates status file" {
    save_status "42" "running" "pi-issue-42"
    [ -f "$TEST_WORKTREE_DIR/.status/42.json" ]
}

@test "save_status writes issue number" {
    save_status "42" "running" "pi-issue-42"
    grep -q '"issue": 42' "$TEST_WORKTREE_DIR/.status/42.json"
}

@test "save_status writes status" {
    save_status "42" "running" "pi-issue-42"
    grep -q '"status": "running"' "$TEST_WORKTREE_DIR/.status/42.json"
}

@test "save_status writes session" {
    save_status "42" "running" "pi-issue-42"
    grep -q '"session": "pi-issue-42"' "$TEST_WORKTREE_DIR/.status/42.json"
}

@test "save_status with error writes error_message" {
    save_status "43" "error" "pi-issue-43" "Test error message"
    [ -f "$TEST_WORKTREE_DIR/.status/43.json" ]
    grep -q '"error_message":' "$TEST_WORKTREE_DIR/.status/43.json"
    grep -q 'Test error message' "$TEST_WORKTREE_DIR/.status/43.json"
}

# ====================
# load_status テスト
# ====================

@test "load_status returns valid JSON" {
    save_status "42" "running" "pi-issue-42"
    json="$(load_status "42")"
    echo "$json" | grep -q '"issue": 42'
}

# ====================
# get_status_value テスト
# ====================

@test "get_status_value returns running status" {
    save_status "42" "running" "pi-issue-42"
    result="$(get_status_value "42")"
    [ "$result" = "running" ]
}

@test "get_status_value returns error status" {
    save_status "43" "error" "pi-issue-43" "Test error"
    result="$(get_status_value "43")"
    [ "$result" = "error" ]
}

@test "get_status_value returns unknown for non-existent" {
    result="$(get_status_value "999")"
    [ "$result" = "unknown" ]
}

# ====================
# get_error_message テスト
# ====================

@test "get_error_message returns error message" {
    save_status "43" "error" "pi-issue-43" "Test error message"
    result="$(get_error_message "43")"
    # トリムして比較
    result_trimmed="${result%% }"
    [ "$result_trimmed" = "Test error message" ]
}

@test "get_error_message returns empty for non-error" {
    save_status "42" "running" "pi-issue-42"
    result="$(get_error_message "42")"
    [ -z "$result" ]
}

# ====================
# remove_status テスト
# ====================

@test "remove_status removes file" {
    save_status "42" "running" "pi-issue-42"
    remove_status "42"
    result="$(get_status_value "42")"
    [ "$result" = "unknown" ]
}

# ====================
# プラットフォーム検出テスト
# ====================

@test "is_macos returns correct value on current platform" {
    if [[ "$(uname)" == "Darwin" ]]; then
        is_macos
    else
        ! is_macos
    fi
}

@test "is_linux returns correct value on current platform" {
    if [[ "$(uname)" == "Linux" ]]; then
        is_linux
    else
        ! is_linux
    fi
}

# ====================
# JSON エスケープテスト
# ====================

@test "save_status with special characters produces valid JSON" {
    save_status "44" "error" "pi-issue-44" 'Error with "quotes" and \backslash'
    
    if command -v jq &>/dev/null; then
        cat "$TEST_WORKTREE_DIR/.status/44.json" | jq . > /dev/null 2>&1
    else
        skip "jq not installed"
    fi
}

# ====================
# handle_complete テスト
# ====================

@test "handle_complete deletes plan file" {
    # Git リポジトリをセットアップ
    cd "$BATS_TEST_TMPDIR"
    git init test-repo &>/dev/null
    cd test-repo
    git config user.email "test@example.com" &>/dev/null
    git config user.name "Test User" &>/dev/null
    
    # 計画書ディレクトリとファイルを作成
    mkdir -p docs/plans
    echo "# Plan for issue 42" > docs/plans/issue-42-plan.md
    git add -A &>/dev/null
    git commit -m "Add plan" &>/dev/null
    
    # worktreeベースディレクトリを設定
    mkdir -p .worktrees/.status
    export TEST_WORKTREE_DIR=".worktrees"
    
    # get_config をオーバーライド（すでにsetupでやっているが念のため）
    get_config() {
        case "$1" in
            worktree_base_dir) echo ".worktrees" ;;
            *) echo "" ;;
        esac
    }
    
    # テスト前に計画書が存在することを確認
    [ -f "docs/plans/issue-42-plan.md" ]
    
    # handle_complete を実行
    handle_complete "pi-issue-42" "42"
    
    # 計画書が削除されたことを確認
    [ ! -f "docs/plans/issue-42-plan.md" ]
}

@test "handle_complete handles missing plan file gracefully" {
    # Git リポジトリをセットアップ
    cd "$BATS_TEST_TMPDIR"
    git init test-repo2 &>/dev/null
    cd test-repo2
    git config user.email "test@example.com" &>/dev/null
    git config user.name "Test User" &>/dev/null
    
    # 初期コミット
    echo "test" > README.md
    git add -A &>/dev/null
    git commit -m "Initial commit" &>/dev/null
    
    # worktreeベースディレクトリを設定
    mkdir -p .worktrees/.status
    export TEST_WORKTREE_DIR=".worktrees"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo ".worktrees" ;;
            *) echo "" ;;
        esac
    }
    
    # 計画書が存在しない状態でhandle_completeを実行（エラーにならないこと）
    run handle_complete "pi-issue-99" "99"
    [ "$status" -eq 0 ]
}
