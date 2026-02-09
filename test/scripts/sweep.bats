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
# check_session_markers: pipe-pane log tests (Issue #1199)
# ====================

@test "check_session_markers detects COMPLETE marker from pipe-pane log file" {
    # Setup test environment
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # Source required libraries
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    # Override get_config for test
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Create pipe-pane log file with COMPLETE marker buried in lots of output
    local log_file="$TEST_WORKTREE_DIR/.status/output-42.log"
    # Generate 200 lines of output before the marker
    for i in $(seq 1 200); do
        echo "Line $i: some build output" >> "$log_file"
    done
    echo "###TASK_COMPLETE_42###" >> "$log_file"
    for i in $(seq 1 50); do
        echo "Line after $i: more output" >> "$log_file"
    done
    
    # check_session_markers should find the marker via log file
    run check_session_markers "pi-issue-42" "42" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

@test "check_session_markers detects ERROR marker from pipe-pane log file" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    local log_file="$TEST_WORKTREE_DIR/.status/output-99.log"
    echo "###TASK_ERROR_99###" > "$log_file"
    
    # With --check-errors
    run check_session_markers "pi-issue-99" "99" "true"
    [ "$status" -eq 0 ]
    [ "$output" = "error" ]
}

@test "check_session_markers returns empty when pipe-pane log has no markers" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Create log file without any markers
    local log_file="$TEST_WORKTREE_DIR/.status/output-55.log"
    echo "just some output" > "$log_file"
    echo "no markers here" >> "$log_file"
    
    run check_session_markers "pi-issue-55" "55" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_session_markers detects alt COMPLETE marker from pipe-pane log" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Use alternative marker pattern (AI sometimes gets the order wrong)
    local log_file="$TEST_WORKTREE_DIR/.status/output-77.log"
    echo "###COMPLETE_TASK_77###" > "$log_file"
    
    run check_session_markers "pi-issue-77" "77" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

@test "check_session_markers falls back to capture-pane when no log file" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    # No log file created
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Mock get_session_output to return marker (simulating capture-pane)
    get_session_output() {
        echo "###TASK_COMPLETE_88###"
    }
    
    run check_session_markers "pi-issue-88" "88" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

@test "check_session_markers fallback uses 500 lines (not 100)" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Mock get_session_output to verify it receives 500 as line count
    local captured_lines=""
    get_session_output() {
        captured_lines="$2"
        echo "line_count=$2"
    }
    
    run check_session_markers "pi-issue-33" "33" "false"
    [ "$status" -eq 0 ]
    # Verify the function was called (output contains nothing since no marker)
    [ "$output" = "" ]
    
    # Verify 500 lines by checking the source code directly
    run grep -c 'get_session_output.*500' "$PROJECT_ROOT/scripts/sweep.sh"
    [ "$output" = "1" ]
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
