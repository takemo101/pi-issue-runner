#!/usr/bin/env bats
# test/lib/improve/execution.bats - Unit tests for lib/improve/execution.sh

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # Create mock SCRIPT_DIR
    export SCRIPT_DIR="$MOCK_DIR/scripts"
    mkdir -p "$SCRIPT_DIR"
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
# Module Loading Tests
# ====================

@test "execution.sh can be sourced" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        echo 'success'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "execution.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/improve/execution.sh"
    [ "$status" -eq 0 ]
}

@test "execution.sh sets strict mode" {
    grep -q 'set -euo pipefail' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "execution.sh uses file-based tracking (no ACTIVE_ISSUE_NUMBERS array)" {
    # Verify the array declaration has been removed (refactored to file-based tracking)
    ! grep -q 'declare -a ACTIVE_ISSUE_NUMBERS' "$PROJECT_ROOT/lib/improve/execution.sh"
}

# ====================
# cleanup_improve_on_exit() Tests
# ====================

@test "cleanup_improve_on_exit does nothing on normal exit (exit_code=0)" {
    # Create mock cleanup.sh that should NOT be called
    cat > "$SCRIPT_DIR/cleanup.sh" << 'EOF'
#!/usr/bin/env bash
echo "ERROR: cleanup should not be called on normal exit"
exit 1
EOF
    chmod +x "$SCRIPT_DIR/cleanup.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Mock list_issues_by_status to return some issues
        list_issues_by_status() {
            echo '42'
            echo '43'
        }
        export -f list_issues_by_status
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        cleanup_improve_on_exit
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"ERROR: cleanup should not be called"* ]]
}

@test "cleanup_improve_on_exit cleans up active sessions on error exit" {
    # Verify the code checks exit_code and cleans up when non-zero
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" == *'exit_code=$?'* ]]
    [[ "$source_content" == *'exit_code -ne 0'* ]]
    [[ "$source_content" == *'cleanup.sh'* ]]
    [[ "$source_content" == *'list_issues_by_status'* ]]
}

@test "cleanup_improve_on_exit handles no active sessions gracefully" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Mock list_issues_by_status to return no issues
        list_issues_by_status() {
            return 0
        }
        export -f list_issues_by_status
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        
        # Simulate error exit
        (exit 1)
        cleanup_improve_on_exit
    "
    [ "$status" -eq 1 ]
    # Should not show "Interrupted" message when no sessions active
    [[ "$output" != *"Interrupted"* ]]
}

@test "cleanup_improve_on_exit uses --force flag" {
    grep -q 'cleanup.sh.*--force' "$PROJECT_ROOT/lib/improve/execution.sh"
}

# ====================
# fetch_improve_created_issues() Tests
# ====================

@test "fetch_improve_created_issues returns issue numbers when found" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        
        # Mock get_issues_created_after
        get_issues_created_after() {
            echo '42'
            echo '43'
            echo '44'
        }
        export -f get_issues_created_after
        
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        fetch_improve_created_issues '2026-01-01T00:00:00Z' 5 'test-label' 2>/dev/null
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"42"* ]]
    [[ "$output" == *"43"* ]]
    [[ "$output" == *"44"* ]]
}

@test "fetch_improve_created_issues exits when no issues found" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        
        # Mock get_issues_created_after to return empty
        get_issues_created_after() {
            echo ''
        }
        export -f get_issues_created_after
        
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        fetch_improve_created_issues '2026-01-01T00:00:00Z' 5 'test-label'
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"No new Issues created"* ]]
    [[ "$output" == *"Improvement complete"* ]]
}

@test "fetch_improve_created_issues filters out invalid issue numbers" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        
        # Mock get_issues_created_after with mixed valid/invalid
        get_issues_created_after() {
            echo '42'
            echo 'invalid'
            echo '43'
            echo ''
            echo 'not-a-number'
            echo '44'
        }
        export -f get_issues_created_after
        
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        fetch_improve_created_issues '2026-01-01T00:00:00Z' 5 'test-label' 2>/dev/null
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"42"* ]]
    [[ "$output" == *"43"* ]]
    [[ "$output" == *"44"* ]]
    [[ "$output" != *"invalid"* ]]
    [[ "$output" != *"not-a-number"* ]]
}

@test "fetch_improve_created_issues logs to stderr not stdout" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        
        get_issues_created_after() {
            echo '42'
        }
        export -f get_issues_created_after
        
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        # Capture only stdout
        fetch_improve_created_issues '2026-01-01T00:00:00Z' 5 'test-label' 2>/dev/null
    "
    [ "$status" -eq 0 ]
    # Only issue numbers should be in stdout
    [[ "$output" == "42" ]]
}

@test "fetch_improve_created_issues shows phase message" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        
        get_issues_created_after() {
            echo '42'
        }
        export -f get_issues_created_after
        
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        # Capture stderr
        fetch_improve_created_issues '2026-01-01T00:00:00Z' 5 'test-label' 2>&1 >/dev/null
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"[PHASE 2]"* ]]
    [[ "$output" == *"Fetching Issues"* ]]
}

# ====================
# execute_improve_issues_in_parallel() Tests
# ====================

@test "execute_improve_issues_in_parallel starts sessions for each issue" {
    # Create mock run.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local run_sh_backup=""
    if [[ -f "$mock_scripts_dir/run.sh" ]]; then
        run_sh_backup="$BATS_TEST_TMPDIR/run.sh.backup"
        cp "$mock_scripts_dir/run.sh" "$run_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/run.sh" << 'EOF'
#!/usr/bin/env bash
echo "started: $1"
exit 0
EOF
    chmod +x "$mock_scripts_dir/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Stub functions needed by _wait_for_available_slot
        get_config() { echo '0'; }
        count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        
        issues=\$'42\n43\n44'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    local test_status=$status
    
    # Restore original run.sh if it existed
    if [[ -n "$run_sh_backup" && -f "$run_sh_backup" ]]; then
        mv "$run_sh_backup" "$mock_scripts_dir/run.sh"
    else
        rm -f "$mock_scripts_dir/run.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"started: 42"* ]]
    [[ "$output" == *"started: 43"* ]]
    [[ "$output" == *"started: 44"* ]]
}

@test "execute_improve_issues_in_parallel uses --no-attach flag" {
    grep -q 'run.sh.*--no-attach' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "execute_improve_issues_in_parallel handles empty issue list" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        execute_improve_issues_in_parallel '' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"No issues to execute"* ]]
}

@test "execute_improve_issues_in_parallel starts sessions (tracked via status files)" {
    # Create mock run.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local run_sh_backup=""
    if [[ -f "$mock_scripts_dir/run.sh" ]]; then
        run_sh_backup="$BATS_TEST_TMPDIR/run.sh.backup"
        cp "$mock_scripts_dir/run.sh" "$run_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/run.sh" << 'EOF'
#!/usr/bin/env bash
# Simulates run.sh saving status
echo "Session started for issue $1"
exit 0
EOF
    chmod +x "$mock_scripts_dir/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        list_issues_by_status() { echo ''; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        
        issues=\$'42\n43'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    local test_status=$status
    
    # Restore original run.sh if it existed
    if [[ -n "$run_sh_backup" && -f "$run_sh_backup" ]]; then
        mv "$run_sh_backup" "$mock_scripts_dir/run.sh"
    else
        rm -f "$mock_scripts_dir/run.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"Session started for issue 42"* ]]
    [[ "$output" == *"Session started for issue 43"* ]]
}

@test "execute_improve_issues_in_parallel warns on session start failure" {
    # Create mock run.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local run_sh_backup=""
    if [[ -f "$mock_scripts_dir/run.sh" ]]; then
        run_sh_backup="$BATS_TEST_TMPDIR/run.sh.backup"
        cp "$mock_scripts_dir/run.sh" "$run_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/run.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$mock_scripts_dir/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        
        issues='42'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    local test_status=$status
    
    # Restore original run.sh if it existed
    if [[ -n "$run_sh_backup" && -f "$run_sh_backup" ]]; then
        mv "$run_sh_backup" "$mock_scripts_dir/run.sh"
    else
        rm -f "$mock_scripts_dir/run.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"Failed to start session for Issue #42"* ]]
}

@test "execute_improve_issues_in_parallel warns on failed session start" {
    # Create mock run.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local run_sh_backup=""
    if [[ -f "$mock_scripts_dir/run.sh" ]]; then
        run_sh_backup="$BATS_TEST_TMPDIR/run.sh.backup"
        cp "$mock_scripts_dir/run.sh" "$run_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/run.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$mock_scripts_dir/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        list_issues_by_status() { echo ''; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        
        issues='42'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    local test_status=$status
    
    # Restore original run.sh if it existed
    if [[ -n "$run_sh_backup" && -f "$run_sh_backup" ]]; then
        mv "$run_sh_backup" "$mock_scripts_dir/run.sh"
    else
        rm -f "$mock_scripts_dir/run.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"Failed to start session for Issue #42"* ]]
}

# ====================
# _wait_for_available_slot() Tests
# ====================

@test "_wait_for_available_slot returns immediately when no limit configured" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        list_issues_by_status() {
            echo '100'
            echo '101'
            echo '102'
            echo '103'
            echo '104'
        }
        export -f list_issues_by_status
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        _wait_for_available_slot 1
        echo 'done'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"done"* ]]
}

@test "_wait_for_available_slot returns immediately when under limit" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '2'; }
        list_issues_by_status() {
            echo '100'
        }
        export -f list_issues_by_status
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        _wait_for_available_slot 1
        echo 'done'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"done"* ]]
}

@test "_wait_for_available_slot waits then proceeds when slot opens" {
    local counter_file="$BATS_TEST_TMPDIR/call_count"
    echo "0" > "$counter_file"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '2'; }
        generate_session_name() { echo \"pi-issue-\$1\"; }
        mux_session_exists() { return 0; }
        COUNTER_FILE='$counter_file'
        list_issues_by_status() {
            local count=\$(cat \"\$COUNTER_FILE\")
            count=\$((count + 1))
            echo \"\$count\" > \"\$COUNTER_FILE\"
            if [[ \$count -le 1 ]]; then
                echo '100'
                echo '101'
            else
                echo '100'
            fi
        }
        export -f list_issues_by_status
        get_status_value() { echo 'complete'; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        _wait_for_available_slot 1
        echo 'done'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Concurrent limit (2) reached"* ]]
    [[ "$output" == *"done"* ]]
}

@test "execute_improve_issues_in_parallel waits for slot when concurrent limit reached" {
    # Create mock run.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local run_sh_backup=""
    if [[ -f "$mock_scripts_dir/run.sh" ]]; then
        run_sh_backup="$BATS_TEST_TMPDIR/run.sh.backup"
        cp "$mock_scripts_dir/run.sh" "$run_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/run.sh" << 'EOF'
#!/usr/bin/env bash
echo "started: $1"
exit 0
EOF
    chmod +x "$mock_scripts_dir/run.sh"
    
    local counter_file="$BATS_TEST_TMPDIR/call_count"
    echo "0" > "$counter_file"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '2'; }
        generate_session_name() { echo \"pi-issue-\$1\"; }
        mux_session_exists() { return 0; }
        COUNTER_FILE='$counter_file'
        # Simulate: first 2 calls under limit, 3rd at limit, then drops
        list_issues_by_status() {
            local count=\$(cat \"\$COUNTER_FILE\")
            count=\$((count + 1))
            echo \"\$count\" > \"\$COUNTER_FILE\"
            if [[ \$count -le 2 ]]; then
                echo ''
            elif [[ \$count -le 3 ]]; then
                echo '100'
                echo '101'
            else
                echo '100'
            fi
        }
        export -f list_issues_by_status
        get_status_value() { echo 'complete'; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        
        issues=\$'42\n43\n44'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    local test_status=$status
    
    # Restore original run.sh if it existed
    if [[ -n "$run_sh_backup" && -f "$run_sh_backup" ]]; then
        mv "$run_sh_backup" "$mock_scripts_dir/run.sh"
    else
        rm -f "$mock_scripts_dir/run.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"started: 42"* ]]
    [[ "$output" == *"started: 43"* ]]
    [[ "$output" == *"Concurrent limit (2) reached"* ]]
    [[ "$output" == *"started: 44"* ]]
}

# ====================
# wait_for_improve_completion() Tests
# ====================

@test "wait_for_improve_completion calls wait-for-sessions.sh" {
    grep -q 'wait-for-sessions.sh' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "wait_for_improve_completion uses --timeout flag" {
    grep -q 'wait-for-sessions.sh.*--timeout' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "wait_for_improve_completion uses --cleanup flag" {
    grep -q 'wait-for-sessions.sh.*--cleanup' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "wait_for_improve_completion handles no active sessions" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Mock list_issues_by_status to return no issues
        list_issues_by_status() {
            return 0
        }
        export -f list_issues_by_status
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        wait_for_improve_completion 3600 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active sessions to wait for"* ]]
}

@test "wait_for_improve_completion waits for all active sessions" {
    # Create mock wait-for-sessions.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local wait_sh_backup=""
    if [[ -f "$mock_scripts_dir/wait-for-sessions.sh" ]]; then
        wait_sh_backup="$BATS_TEST_TMPDIR/wait-for-sessions.sh.backup"
        cp "$mock_scripts_dir/wait-for-sessions.sh" "$wait_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/wait-for-sessions.sh" << 'EOF'
#!/usr/bin/env bash
echo "waiting for: $@"
exit 0
EOF
    chmod +x "$mock_scripts_dir/wait-for-sessions.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Mock list_issues_by_status to return running issues
        list_issues_by_status() {
            echo '42'
            echo '43'
            echo '44'
        }
        export -f list_issues_by_status
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        wait_for_improve_completion 3600 2>&1
    "
    local test_status=$status
    
    # Restore original wait-for-sessions.sh if it existed
    if [[ -n "$wait_sh_backup" && -f "$wait_sh_backup" ]]; then
        mv "$wait_sh_backup" "$mock_scripts_dir/wait-for-sessions.sh"
    else
        rm -f "$mock_scripts_dir/wait-for-sessions.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"waiting for: 42 43 44"* ]]
}

@test "wait_for_improve_completion uses file-based tracking" {
    # Create mock wait-for-sessions.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local wait_sh_backup=""
    if [[ -f "$mock_scripts_dir/wait-for-sessions.sh" ]]; then
        wait_sh_backup="$BATS_TEST_TMPDIR/wait-for-sessions.sh.backup"
        cp "$mock_scripts_dir/wait-for-sessions.sh" "$wait_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/wait-for-sessions.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$mock_scripts_dir/wait-for-sessions.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Mock list_issues_by_status to return running issues
        list_issues_by_status() {
            echo '42'
            echo '43'
        }
        export -f list_issues_by_status
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        wait_for_improve_completion 3600 2>&1
    "
    local test_status=$status
    
    # Restore original wait-for-sessions.sh if it existed
    if [[ -n "$wait_sh_backup" && -f "$wait_sh_backup" ]]; then
        mv "$wait_sh_backup" "$mock_scripts_dir/wait-for-sessions.sh"
    else
        rm -f "$mock_scripts_dir/wait-for-sessions.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"Waiting for: 42 43"* ]]
}

@test "wait_for_improve_completion warns on failure" {
    # Create mock wait-for-sessions.sh at the actual computed location
    local mock_scripts_dir="$PROJECT_ROOT/scripts"
    mkdir -p "$mock_scripts_dir"
    local wait_sh_backup=""
    if [[ -f "$mock_scripts_dir/wait-for-sessions.sh" ]]; then
        wait_sh_backup="$BATS_TEST_TMPDIR/wait-for-sessions.sh.backup"
        cp "$mock_scripts_dir/wait-for-sessions.sh" "$wait_sh_backup"
    fi
    
    cat > "$mock_scripts_dir/wait-for-sessions.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$mock_scripts_dir/wait-for-sessions.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Mock list_issues_by_status to return running issue
        list_issues_by_status() {
            echo '42'
        }
        export -f list_issues_by_status
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        wait_for_improve_completion 3600 2>&1
    "
    local test_status=$status
    
    # Restore original wait-for-sessions.sh if it existed
    if [[ -n "$wait_sh_backup" && -f "$wait_sh_backup" ]]; then
        mv "$wait_sh_backup" "$mock_scripts_dir/wait-for-sessions.sh"
    else
        rm -f "$mock_scripts_dir/wait-for-sessions.sh"
    fi
    
    [ "$test_status" -eq 0 ]
    [[ "$output" == *"Some sessions failed or timed out"* ]]
}

# ====================
# start_improve_next_iteration() Tests
# ====================

@test "start_improve_next_iteration uses exec for recursion" {
    grep -q 'exec "$0"' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "start_improve_next_iteration increments iteration number" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" =~ \$\(\(iteration\ \+\ 1\)\) ]]
}

@test "start_improve_next_iteration preserves all parameters" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" == *"--max-iterations"* ]]
    [[ "$source_content" == *"--max-issues"* ]]
    [[ "$source_content" == *"--timeout"* ]]
    [[ "$source_content" == *"--log-dir"* ]]
    [[ "$source_content" == *"--label"* ]]
}

@test "start_improve_next_iteration preserves --auto-continue flag" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    # Should conditionally add --auto-continue based on the flag
    [[ "$source_content" =~ auto_continue.*==.*true.*--auto-continue ]]
}

@test "start_improve_next_iteration shows phase message" {
    grep -q '\[PHASE 5\]' "$PROJECT_ROOT/lib/improve/execution.sh"
}

# ====================
# Backward Compatibility Tests
# ====================

@test "cleanup_on_exit() is backward compatible wrapper" {
    grep -q 'cleanup_on_exit()' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "fetch_created_issues() is backward compatible wrapper" {
    grep -q 'fetch_created_issues()' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "execute_issues_in_parallel() is backward compatible wrapper" {
    grep -q 'execute_issues_in_parallel()' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "wait_for_completion() is backward compatible wrapper" {
    grep -q 'wait_for_completion()' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "start_next_iteration() is backward compatible wrapper" {
    grep -q 'start_next_iteration()' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "all backward compatibility wrappers call new function names" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    
    # Check each wrapper calls the _improve_ version
    [[ "$source_content" =~ cleanup_on_exit\(\).*cleanup_improve_on_exit ]]
    [[ "$source_content" =~ fetch_created_issues\(\).*fetch_improve_created_issues ]]
    [[ "$source_content" =~ execute_issues_in_parallel\(\).*execute_improve_issues_in_parallel ]]
    [[ "$source_content" =~ wait_for_completion\(\).*wait_for_improve_completion ]]
    [[ "$source_content" =~ start_next_iteration\(\).*start_improve_next_iteration ]]
}

# ====================
# Phase Markers Tests
# ====================

@test "execution.sh uses phase markers for output" {
    grep -q '\[PHASE 2\]' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q '\[PHASE 3\]' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q '\[PHASE 4\]' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q '\[PHASE 5\]' "$PROJECT_ROOT/lib/improve/execution.sh"
}
