#!/usr/bin/env bats
# lock.sh のBatsテスト

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
    source "$PROJECT_ROOT/lib/lock.sh"
    
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
    # テストで作成したロックをクリーンアップ
    rm -rf "$TEST_WORKTREE_DIR/.status"/*.cleanup.lock 2>/dev/null || true
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# acquire_cleanup_lock テスト
# ====================

@test "acquire_cleanup_lock creates lock directory" {
    run acquire_cleanup_lock "100"
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREE_DIR/.status/100.cleanup.lock" ]
}

@test "acquire_cleanup_lock writes current PID" {
    acquire_cleanup_lock "101"
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/101.cleanup.lock/pid")
    [ "$pid" = "$$" ]
}

@test "acquire_cleanup_lock fails when already locked by live process" {
    # Create a lock with current process PID (which is alive)
    mkdir -p "$TEST_WORKTREE_DIR/.status/102.cleanup.lock"
    echo $$ > "$TEST_WORKTREE_DIR/.status/102.cleanup.lock/pid"
    
    # Second acquire from same PID should fail (mkdir fails)
    # but stale check passes since PID is alive, so it stays locked
    run acquire_cleanup_lock "102"
    [ "$status" -eq 1 ]
}

@test "acquire_cleanup_lock takes over stale lock" {
    # Create a lock with dead PID
    mkdir -p "$TEST_WORKTREE_DIR/.status/103.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/103.cleanup.lock/pid"
    
    run acquire_cleanup_lock "103"
    [ "$status" -eq 0 ]
    
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/103.cleanup.lock/pid")
    [ "$pid" = "$$" ]
}

# ====================
# release_cleanup_lock テスト
# ====================

@test "release_cleanup_lock removes own lock" {
    acquire_cleanup_lock "200"
    [ -d "$TEST_WORKTREE_DIR/.status/200.cleanup.lock" ]
    
    release_cleanup_lock "200"
    [ ! -d "$TEST_WORKTREE_DIR/.status/200.cleanup.lock" ]
}

@test "release_cleanup_lock handles non-existent lock gracefully" {
    run release_cleanup_lock "201"
    [ "$status" -eq 0 ]
}

@test "release_cleanup_lock removes stale lock from dead process" {
    mkdir -p "$TEST_WORKTREE_DIR/.status/202.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/202.cleanup.lock/pid"
    
    release_cleanup_lock "202"
    [ ! -d "$TEST_WORKTREE_DIR/.status/202.cleanup.lock" ]
}

# ====================
# is_cleanup_locked テスト
# ====================

@test "is_cleanup_locked returns true for active lock" {
    acquire_cleanup_lock "300"
    run is_cleanup_locked "300"
    [ "$status" -eq 0 ]
}

@test "is_cleanup_locked returns false for no lock" {
    run is_cleanup_locked "301"
    [ "$status" -eq 1 ]
}

@test "is_cleanup_locked returns false for stale lock" {
    mkdir -p "$TEST_WORKTREE_DIR/.status/302.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/302.cleanup.lock/pid"
    
    run is_cleanup_locked "302"
    [ "$status" -eq 1 ]
}

# ====================
# lock.sh standalone source テスト
# ====================

@test "lock.sh can be sourced independently" {
    # Verify functions are available when sourcing lock.sh directly
    run bash -c "
        source '$PROJECT_ROOT/lib/lock.sh'
        declare -f acquire_cleanup_lock > /dev/null && echo 'ok'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "lock.sh source guard prevents double loading" {
    run bash -c "
        source '$PROJECT_ROOT/lib/lock.sh'
        source '$PROJECT_ROOT/lib/lock.sh'
        echo 'ok'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
