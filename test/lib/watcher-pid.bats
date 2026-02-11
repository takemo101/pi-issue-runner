#!/usr/bin/env bats
# watcher-pid.sh のBatsテスト

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
    source "$PROJECT_ROOT/lib/watcher-pid.sh"
    
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
# save_watcher_pid テスト
# ====================

@test "save_watcher_pid creates PID file" {
    save_watcher_pid "100" "12345"
    [ -f "$TEST_WORKTREE_DIR/.status/100.watcher.pid" ]
    local content
    content=$(cat "$TEST_WORKTREE_DIR/.status/100.watcher.pid")
    [ "$content" = "12345" ]
}

@test "save_watcher_pid overwrites existing PID" {
    save_watcher_pid "101" "11111"
    save_watcher_pid "101" "22222"
    local content
    content=$(cat "$TEST_WORKTREE_DIR/.status/101.watcher.pid")
    [ "$content" = "22222" ]
}

@test "save_watcher_pid uses atomic write (no temp file remains)" {
    save_watcher_pid "102" "12345"
    local tmp_files
    tmp_files=$(find "$TEST_WORKTREE_DIR/.status" -name "102.watcher.pid.tmp.*" | wc -l)
    [ "$tmp_files" -eq 0 ]
}

# ====================
# load_watcher_pid テスト
# ====================

@test "load_watcher_pid returns saved PID" {
    save_watcher_pid "200" "54321"
    result="$(load_watcher_pid "200")"
    [ "$result" = "54321" ]
}

@test "load_watcher_pid returns empty for non-existent PID file" {
    result="$(load_watcher_pid "999")"
    [ -z "$result" ]
}

# ====================
# remove_watcher_pid テスト
# ====================

@test "remove_watcher_pid deletes PID file" {
    save_watcher_pid "300" "99999"
    [ -f "$TEST_WORKTREE_DIR/.status/300.watcher.pid" ]
    
    remove_watcher_pid "300"
    [ ! -f "$TEST_WORKTREE_DIR/.status/300.watcher.pid" ]
}

@test "remove_watcher_pid handles non-existent file gracefully" {
    run remove_watcher_pid "999"
    [ "$status" -eq 0 ]
}

# ====================
# is_watcher_running テスト
# ====================

@test "is_watcher_running returns false for non-existent PID" {
    run is_watcher_running "400"
    [ "$status" -eq 1 ]
}

@test "is_watcher_running returns true for current process" {
    save_watcher_pid "401" "$$"
    run is_watcher_running "401"
    [ "$status" -eq 0 ]
}

@test "is_watcher_running returns false for dead PID" {
    save_watcher_pid "402" "999999"
    run is_watcher_running "402"
    [ "$status" -eq 1 ]
}

# ====================
# watcher-pid.sh standalone source テスト
# ====================

@test "watcher-pid.sh can be sourced independently" {
    run bash -c "
        source '$PROJECT_ROOT/lib/watcher-pid.sh'
        declare -f save_watcher_pid > /dev/null && echo 'ok'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "watcher-pid.sh source guard prevents double loading" {
    run bash -c "
        source '$PROJECT_ROOT/lib/watcher-pid.sh'
        source '$PROJECT_ROOT/lib/watcher-pid.sh'
        echo 'ok'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
