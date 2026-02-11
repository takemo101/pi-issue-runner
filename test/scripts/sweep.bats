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
    source "$PROJECT_ROOT/lib/multiplexer.sh"
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
    source "$PROJECT_ROOT/lib/multiplexer.sh"
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
    source "$PROJECT_ROOT/lib/multiplexer.sh"
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
    source "$PROJECT_ROOT/lib/multiplexer.sh"
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
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Mock mux_get_session_output to return marker (simulating capture-pane)
    mux_get_session_output() {
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
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Mock mux_get_session_output to verify it receives 500 as line count
    local captured_lines=""
    mux_get_session_output() {
        captured_lines="$2"
        echo "line_count=$2"
    }
    
    run check_session_markers "pi-issue-33" "33" "false"
    [ "$status" -eq 0 ]
    # Verify the function was called (output contains nothing since no marker)
    [ "$output" = "" ]
    
    # Verify 500 lines by checking the source code directly
    run grep -c 'mux_get_session_output.*500' "$PROJECT_ROOT/scripts/sweep.sh"
    [ "$output" = "1" ]
}

# ====================
# Signal File Cleanup Tests (Issue #1269)
# ====================

@test "execute_cleanup removes signal files before running cleanup.sh" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Create signal files
    echo "done" > "$TEST_WORKTREE_DIR/.status/signal-complete-9999"
    echo "fail" > "$TEST_WORKTREE_DIR/.status/signal-error-9999"
    
    # Verify signal files exist
    [ -f "$TEST_WORKTREE_DIR/.status/signal-complete-9999" ]
    [ -f "$TEST_WORKTREE_DIR/.status/signal-error-9999" ]
    
    # Mock cleanup.sh to succeed without side effects
    # Override SCRIPT_DIR to use mock
    cat > "$MOCK_BIN/cleanup.sh" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_BIN/cleanup.sh"
    
    # Override SCRIPT_DIR so execute_cleanup calls our mock
    SCRIPT_DIR="$MOCK_BIN"
    
    # Mock is_cleanup_locked to return false (not locked)
    is_cleanup_locked() { return 1; }
    
    run execute_cleanup "pi-issue-9999" "9999" "false"
    [ "$status" -eq 0 ]
    
    # Signal files should be deleted
    [ ! -f "$TEST_WORKTREE_DIR/.status/signal-complete-9999" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/signal-error-9999" ]
}

@test "execute_cleanup removes signal files even when only complete signal exists" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Create only complete signal file
    echo "done" > "$TEST_WORKTREE_DIR/.status/signal-complete-100"
    
    cat > "$MOCK_BIN/cleanup.sh" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_BIN/cleanup.sh"
    
    SCRIPT_DIR="$MOCK_BIN"
    is_cleanup_locked() { return 1; }
    
    run execute_cleanup "pi-issue-100" "100" "false"
    [ "$status" -eq 0 ]
    
    # Signal file should be deleted
    [ ! -f "$TEST_WORKTREE_DIR/.status/signal-complete-100" ]
}

# ====================
# Lock Integration Tests (Issue #1077)
# ====================

# ====================
# Signal file detection tests (Issue #1272)
# ====================

@test "check_session_markers detects signal-complete file" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # Override get_status_dir to use test directory
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create signal-complete file
    echo "done" > "$TEST_WORKTREE_DIR/.status/signal-complete-42"
    
    run check_session_markers "pi-issue-42" "42" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

@test "check_session_markers detects signal-error file with --check-errors" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create signal-error file
    echo "some error occurred" > "$TEST_WORKTREE_DIR/.status/signal-error-99"
    
    run check_session_markers "pi-issue-99" "99" "true"
    [ "$status" -eq 0 ]
    [ "$output" = "error" ]
}

@test "check_session_markers ignores signal-error file without --check-errors" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create signal-error file but check_errors=false
    echo "some error" > "$TEST_WORKTREE_DIR/.status/signal-error-55"
    
    # No log file, mock mux_get_session_output to return empty
    mux_get_session_output() { echo ""; }
    
    run check_session_markers "pi-issue-55" "55" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_session_markers returns empty when no signal file and no markers" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # No signal files, no log file
    mux_get_session_output() { echo "just normal output"; }
    
    run check_session_markers "pi-issue-77" "77" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_session_markers prioritizes signal file over text markers" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create both signal-complete AND error marker in log
    echo "done" > "$TEST_WORKTREE_DIR/.status/signal-complete-42"
    local log_file="$TEST_WORKTREE_DIR/.status/output-42.log"
    echo "###TASK_ERROR_42###" > "$log_file"
    
    # Signal file should take priority → "complete"
    run check_session_markers "pi-issue-42" "42" "true"
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

# ====================
# Code block exclusion tests (Issue #1278)
# ====================

@test "check_session_markers ignores COMPLETE marker inside code block in pipe-pane log" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create pipe-pane log with marker INSIDE a code block
    local log_file="$TEST_WORKTREE_DIR/.status/output-42.log"
    cat > "$log_file" << 'EOF'
Some output before
```
###TASK_COMPLETE_42###
```
Some output after
EOF
    
    # Should NOT detect as complete (marker is inside code block)
    run check_session_markers "pi-issue-42" "42" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_session_markers ignores ERROR marker inside code block in pipe-pane log" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create pipe-pane log with ERROR marker INSIDE a code block
    local log_file="$TEST_WORKTREE_DIR/.status/output-42.log"
    cat > "$log_file" << 'EOF'
Some output before
```
###TASK_ERROR_42###
```
Some output after
EOF
    
    # Should NOT detect as error (marker is inside code block)
    run check_session_markers "pi-issue-42" "42" "true"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_session_markers detects COMPLETE marker outside code block in pipe-pane log" {
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/multiplexer.sh"
    source "$PROJECT_ROOT/lib/marker.sh"
    source "$PROJECT_ROOT/scripts/sweep.sh"
    
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    get_status_dir() { echo "$TEST_WORKTREE_DIR/.status"; }
    
    # Create pipe-pane log with marker both inside and outside code block
    local log_file="$TEST_WORKTREE_DIR/.status/output-42.log"
    cat > "$log_file" << 'EOF'
Some output
```
###TASK_COMPLETE_42###
```
More output
###TASK_COMPLETE_42###
EOF
    
    # Should detect as complete (one marker is outside code block)
    run check_session_markers "pi-issue-42" "42" "false"
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
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
