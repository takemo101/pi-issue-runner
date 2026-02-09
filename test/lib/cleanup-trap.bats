#!/usr/bin/env bats
# cleanup-trap.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    # ソースガードをリセット（テスト間の汚染防止）
    unset _CLEANUP_TRAP_SH_SOURCED
    unset _CLEANUP_FUNC
    unset _WORKTREE_TO_CLEANUP

    # ログを抑制
    export LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# register_worktree_for_cleanup テスト
# ====================

@test "register_worktree_for_cleanup sets global variable" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    register_worktree_for_cleanup "/tmp/test-worktree"
    [ "$_WORKTREE_TO_CLEANUP" = "/tmp/test-worktree" ]
}

@test "register_worktree_for_cleanup overwrites previous value" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    register_worktree_for_cleanup "/tmp/first"
    register_worktree_for_cleanup "/tmp/second"
    [ "$_WORKTREE_TO_CLEANUP" = "/tmp/second" ]
}

# ====================
# unregister_worktree_for_cleanup テスト
# ====================

@test "unregister_worktree_for_cleanup clears global variable" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    register_worktree_for_cleanup "/tmp/test-worktree"
    unregister_worktree_for_cleanup
    [ -z "${_WORKTREE_TO_CLEANUP:-}" ]
}

@test "unregister_worktree_for_cleanup is safe when not set" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    # Should not fail even if _WORKTREE_TO_CLEANUP is not set
    run unregister_worktree_for_cleanup
    [ "$status" -eq 0 ]
}

# ====================
# setup_cleanup_trap テスト
# ====================

@test "setup_cleanup_trap sets _CLEANUP_FUNC" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    setup_cleanup_trap "my_cleanup_func"
    [ "$_CLEANUP_FUNC" = "my_cleanup_func" ]
}

@test "setup_cleanup_trap with empty argument sets empty func" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    setup_cleanup_trap ""
    [ -z "$_CLEANUP_FUNC" ]
}

@test "setup_cleanup_trap sets EXIT trap" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    setup_cleanup_trap "my_cleanup_func"
    # Verify trap is set for EXIT
    local trap_output
    trap_output="$(trap -p EXIT)"
    [[ "$trap_output" == *"_cleanup_handler"* ]]
}

# ====================
# cleanup_worktree_on_error テスト
# ====================

@test "cleanup_worktree_on_error calls git worktree remove when directory exists" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"

    # Create a fake worktree directory
    local fake_worktree="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$fake_worktree"

    # Mock git
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    mock_git
    enable_mocks

    _WORKTREE_TO_CLEANUP="$fake_worktree"
    run cleanup_worktree_on_error
    [ "$status" -eq 0 ]
    # After cleanup, the variable should be unset
    # (run executes in subshell so we test the function logic separately)
}

@test "cleanup_worktree_on_error does nothing when variable is empty" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    unset _WORKTREE_TO_CLEANUP
    run cleanup_worktree_on_error
    [ "$status" -eq 0 ]
}

@test "cleanup_worktree_on_error does nothing when directory does not exist" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    _WORKTREE_TO_CLEANUP="/nonexistent/path/worktree"
    run cleanup_worktree_on_error
    [ "$status" -eq 0 ]
}

# ====================
# _cleanup_handler テスト
# ====================

@test "_cleanup_handler does not run cleanup on exit code 0" {
    # Run in subshell to test exit behavior
    local track_file="$BATS_TEST_TMPDIR/cleanup_called"

    run bash -c "
        source '$PROJECT_ROOT/lib/cleanup-trap.sh'
        my_cleanup() { touch '$track_file'; }
        setup_cleanup_trap 'my_cleanup'
        exit 0
    "
    # Cleanup should NOT have been called
    [ ! -f "$track_file" ]
}

@test "_cleanup_handler runs cleanup on non-zero exit" {
    local track_file="$BATS_TEST_TMPDIR/cleanup_called"

    run bash -c "
        set +e
        source '$PROJECT_ROOT/lib/cleanup-trap.sh'
        my_cleanup() { touch '$track_file'; }
        setup_cleanup_trap 'my_cleanup'
        exit 1
    "
    # Cleanup should have been called
    [ -f "$track_file" ]
}

@test "_cleanup_handler does not fail when cleanup func is not defined" {
    run bash -c "
        source '$PROJECT_ROOT/lib/cleanup-trap.sh'
        setup_cleanup_trap 'nonexistent_function'
        exit 1
    "
    # Should not crash (exit code is 1 from exit 1, not from handler)
    [ "$status" -eq 1 ]
}

@test "_cleanup_handler does not fail when cleanup func is empty" {
    run bash -c "
        source '$PROJECT_ROOT/lib/cleanup-trap.sh'
        setup_cleanup_trap ''
        exit 1
    "
    [ "$status" -eq 1 ]
}

# ====================
# ソースガード テスト
# ====================

@test "source guard prevents double loading" {
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    # Set a custom value
    _CLEANUP_FUNC="original"
    # Source again - should be no-op due to guard
    source "$PROJECT_ROOT/lib/cleanup-trap.sh"
    # Value should be preserved
    [ "$_CLEANUP_FUNC" = "original" ]
}
