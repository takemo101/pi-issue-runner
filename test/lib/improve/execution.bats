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

@test "execution.sh declares ACTIVE_ISSUE_NUMBERS array" {
    grep -q 'declare -a ACTIVE_ISSUE_NUMBERS' "$PROJECT_ROOT/lib/improve/execution.sh"
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
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        ACTIVE_ISSUE_NUMBERS=(42 43)
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
    [[ "$source_content" == *'ACTIVE_ISSUE_NUMBERS'* ]]
}

@test "cleanup_improve_on_exit handles no active sessions gracefully" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        ACTIVE_ISSUE_NUMBERS=()
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
    # Create mock run.sh
    cat > "$SCRIPT_DIR/run.sh" << 'EOF'
#!/usr/bin/env bash
echo "started: $1"
exit 0
EOF
    chmod +x "$SCRIPT_DIR/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        # Stub functions needed by _wait_for_available_slot
        get_config() { echo '0'; }
        mux_count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        
        issues=\$'42\n43\n44'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    [ "$status" -eq 0 ]
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
        mux_count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        execute_improve_issues_in_parallel '' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"No issues to execute"* ]]
}

@test "execute_improve_issues_in_parallel tracks active sessions" {
    # Create mock run.sh that succeeds
    cat > "$SCRIPT_DIR/run.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SCRIPT_DIR/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        mux_count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        
        issues=\$'42\n43'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1 >/dev/null
        
        # Print the array contents
        echo \"ACTIVE_ISSUE_NUMBERS: \${ACTIVE_ISSUE_NUMBERS[*]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE_ISSUE_NUMBERS: 42 43"* ]]
}

@test "execute_improve_issues_in_parallel warns on session start failure" {
    # Create mock run.sh that fails
    cat > "$SCRIPT_DIR/run.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$SCRIPT_DIR/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        mux_count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        
        issues='42'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed to start session for Issue #42"* ]]
}

@test "execute_improve_issues_in_parallel does not track failed sessions" {
    # Create mock run.sh that fails
    cat > "$SCRIPT_DIR/run.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$SCRIPT_DIR/run.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        mux_count_active_sessions() { echo '0'; }
        get_status_value() { echo ''; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        
        issues='42'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1 >/dev/null
        
        # Print the array contents
        echo \"ACTIVE_ISSUE_NUMBERS count: \${#ACTIVE_ISSUE_NUMBERS[@]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE_ISSUE_NUMBERS count: 0"* ]]
}

# ====================
# _wait_for_available_slot() Tests
# ====================

@test "_wait_for_available_slot returns immediately when no limit configured" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '0'; }
        mux_count_active_sessions() { echo '5'; }
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
        mux_count_active_sessions() { echo '1'; }
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
        mux_count_active_sessions() {
            local count=\$(cat \"\$COUNTER_FILE\")
            count=\$((count + 1))
            echo \"\$count\" > \"\$COUNTER_FILE\"
            if [[ \$count -le 1 ]]; then
                echo '2'
            else
                echo '1'
            fi
        }
        get_status_value() { echo 'completed'; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        _wait_for_available_slot 1
        echo 'done'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Concurrent limit (2) reached"* ]]
    [[ "$output" == *"done"* ]]
}

@test "execute_improve_issues_in_parallel waits for slot when concurrent limit reached" {
    # Create mock run.sh that succeeds
    cat > "$SCRIPT_DIR/run.sh" << 'EOF'
#!/usr/bin/env bash
echo "started: $1"
exit 0
EOF
    chmod +x "$SCRIPT_DIR/run.sh"
    
    local counter_file="$BATS_TEST_TMPDIR/call_count"
    echo "0" > "$counter_file"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        get_config() { echo '2'; }
        generate_session_name() { echo \"pi-issue-\$1\"; }
        mux_session_exists() { return 0; }
        COUNTER_FILE='$counter_file'
        # Simulate: first 2 calls under limit, 3rd at limit, then drops
        mux_count_active_sessions() {
            local count=\$(cat \"\$COUNTER_FILE\")
            count=\$((count + 1))
            echo \"\$count\" > \"\$COUNTER_FILE\"
            if [[ \$count -le 2 ]]; then
                echo '0'
            elif [[ \$count -le 3 ]]; then
                echo '2'
            else
                echo '1'
            fi
        }
        get_status_value() { echo 'completed'; }
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        
        issues=\$'42\n43\n44'
        execute_improve_issues_in_parallel \"\$issues\" 2>&1
    "
    [ "$status" -eq 0 ]
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
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        ACTIVE_ISSUE_NUMBERS=()
        wait_for_improve_completion 3600 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active sessions to wait for"* ]]
}

@test "wait_for_improve_completion waits for all active sessions" {
    # Create mock wait-for-sessions.sh
    cat > "$SCRIPT_DIR/wait-for-sessions.sh" << 'EOF'
#!/usr/bin/env bash
echo "waiting for: $@"
exit 0
EOF
    chmod +x "$SCRIPT_DIR/wait-for-sessions.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        ACTIVE_ISSUE_NUMBERS=(42 43 44)
        wait_for_improve_completion 3600 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"waiting for: 42 43 44"* ]]
}

@test "wait_for_improve_completion clears active sessions after completion" {
    # Create mock wait-for-sessions.sh
    cat > "$SCRIPT_DIR/wait-for-sessions.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SCRIPT_DIR/wait-for-sessions.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        ACTIVE_ISSUE_NUMBERS=(42 43)
        wait_for_improve_completion 3600 2>&1 >/dev/null
        echo \"ACTIVE_ISSUE_NUMBERS count: \${#ACTIVE_ISSUE_NUMBERS[@]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE_ISSUE_NUMBERS count: 0"* ]]
}

@test "wait_for_improve_completion warns on failure" {
    # Create mock wait-for-sessions.sh that fails
    cat > "$SCRIPT_DIR/wait-for-sessions.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$SCRIPT_DIR/wait-for-sessions.sh"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/improve/execution.sh'
        export SCRIPT_DIR='$SCRIPT_DIR'
        ACTIVE_ISSUE_NUMBERS=(42)
        wait_for_improve_completion 3600 2>&1
    "
    [ "$status" -eq 0 ]
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
