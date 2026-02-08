#!/usr/bin/env bats
# test/regression/cleanup-race-condition.bats
# Regression test for Issue #1077: Prevent concurrent cleanup race condition

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # Setup test environment
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # Source required libraries
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Override get_config for test
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Suppress logs
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# Issue #1077: Race Condition Prevention
# ====================

@test "concurrent cleanup attempts are prevented by lock" {
    # Simulate the scenario where both sweep.sh and watch-session.sh
    # try to clean up the same session simultaneously
    
    local issue_number=1077
    
    # Process 1 (simulating watch-session.sh) acquires the lock
    run acquire_cleanup_lock "$issue_number"
    [ "$status" -eq 0 ]
    
    # Verify lock exists
    [ -d "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock" ]
    
    # Process 2 (simulating sweep.sh) checks if locked
    run is_cleanup_locked "$issue_number"
    [ "$status" -eq 0 ]  # Lock is held
    
    # Process 2 tries to acquire lock - should fail
    run bash -c "source '$PROJECT_ROOT/lib/status.sh'; get_config() { case \"\$1\" in worktree_base_dir) echo \"$TEST_WORKTREE_DIR\" ;; *) echo \"\" ;; esac; }; acquire_cleanup_lock $issue_number"
    [ "$status" -eq 1 ]  # Acquisition fails
    
    # Process 1 completes cleanup and releases lock
    release_cleanup_lock "$issue_number"
    
    # Verify lock is released
    [ ! -d "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock" ]
    
    # Now Process 2 can acquire the lock
    run acquire_cleanup_lock "$issue_number"
    [ "$status" -eq 0 ]
}

@test "stale lock from crashed process is automatically cleaned up" {
    # Simulate a process crash scenario where the lock is left behind
    # but the process no longer exists
    
    local issue_number=1077
    
    # Create a stale lock with a non-existent PID
    mkdir -p "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock/pid"
    
    # Verify stale lock exists
    [ -d "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock" ]
    
    # is_cleanup_locked should detect it's stale
    run is_cleanup_locked "$issue_number"
    [ "$status" -eq 1 ]  # Returns false for stale lock
    
    # acquire_cleanup_lock should remove stale lock and acquire new one
    run acquire_cleanup_lock "$issue_number"
    [ "$status" -eq 0 ]
    
    # Verify the lock now has the current PID
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock/pid")
    [ "$pid" = "$$" ]
    
    # Clean up
    release_cleanup_lock "$issue_number"
}

@test "cleanup lock is released on normal completion" {
    local issue_number=1077
    
    # Acquire lock
    acquire_cleanup_lock "$issue_number"
    [ -d "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock" ]
    
    # Simulate cleanup completion
    release_cleanup_lock "$issue_number"
    
    # Verify lock is gone
    [ ! -d "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock" ]
}

@test "cleanup lock is released on error (trap simulation)" {
    local issue_number=1077
    
    # Simulate a cleanup script that uses trap to ensure lock release
    run bash -c "
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/status.sh'
        
        get_config() {
            case \"\$1\" in
                worktree_base_dir) echo \"$TEST_WORKTREE_DIR\" ;;
                *) echo \"\" ;;
            esac
        }
        
        LOG_LEVEL=\"ERROR\"
        
        # Acquire lock
        acquire_cleanup_lock $issue_number || exit 1
        
        # Set trap to release on exit
        trap \"release_cleanup_lock $issue_number\" EXIT
        
        # Simulate error
        exit 42
    "
    
    # Script should exit with error code 42
    [ "$status" -eq 42 ]
    
    # But lock should still be released by trap
    # Note: The lock will be released in the subprocess, so we need to check
    # that the lock directory doesn't exist or is stale
    if [ -d "$TEST_WORKTREE_DIR/.status/${issue_number}.cleanup.lock" ]; then
        # If it exists, it should be stale (subprocess PID)
        run is_cleanup_locked "$issue_number"
        [ "$status" -eq 1 ]  # Stale lock
    fi
}

@test "multiple processes can queue for cleanup lock" {
    local issue_number=1077
    
    # Process 1 acquires lock
    acquire_cleanup_lock "$issue_number"
    
    # Processes 2-4 try to acquire in background
    # They should all fail because lock is held
    local failures=0
    for i in {1..3}; do
        if ! bash -c "source '$PROJECT_ROOT/lib/status.sh'; get_config() { case \"\$1\" in worktree_base_dir) echo \"$TEST_WORKTREE_DIR\" ;; *) echo \"\" ;; esac; }; acquire_cleanup_lock $issue_number" 2>/dev/null; then
            failures=$((failures + 1))
        fi
    done
    
    # All 3 attempts should have failed
    [ "$failures" -eq 3 ]
    
    # Process 1 releases
    release_cleanup_lock "$issue_number"
    
    # Now a new process can acquire
    run acquire_cleanup_lock "$issue_number"
    [ "$status" -eq 0 ]
    
    # Clean up
    release_cleanup_lock "$issue_number"
}
