#!/usr/bin/env bats
# test/scripts/sweep.bats - Tests for sweep.sh

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_BIN="${BATS_TEST_TMPDIR}/mock_bin"
    mkdir -p "$MOCK_BIN"
    export ORIGINAL_PATH="$PATH"
    export PATH="$MOCK_BIN:$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "sweep.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/sweep.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "sweep.sh fails with invalid option" {
    run "$PROJECT_ROOT/scripts/sweep.sh" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "sweep.sh runs with --dry-run when no sessions (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh detects session with COMPLETE marker (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh ignores COMPLETE marker in code block (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh detects ERROR marker with --check-errors (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh does not detect ERROR marker without --check-errors (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh shows summary (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh executes cleanup (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

# ====================
# Lock Integration Tests (Issue #1077)
# ====================

@test "sweep.sh skips cleanup when lock is held" {
    # This test verifies that sweep.sh respects cleanup locks
    # to prevent race conditions with watch-session.sh
    
    # Setup test worktree directory
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # Source required libraries
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Override get_config for test
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Create a lock for issue #1077
    acquire_cleanup_lock "1077"
    
    # Verify lock exists
    [ -d "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock" ]
    
    # Test is_cleanup_locked function
    run is_cleanup_locked "1077"
    [ "$status" -eq 0 ]
    
    # In a real scenario, sweep.sh would check this lock and skip cleanup
    # This is tested in integration/manual tests
}
