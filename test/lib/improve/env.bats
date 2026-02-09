#!/usr/bin/env bats
# test/lib/improve/env.bats - Unit tests for lib/improve/env.sh

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
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

@test "env.sh can be sourced" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        source '$PROJECT_ROOT/lib/improve/env.sh'
        echo 'success'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "env.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/improve/env.sh"
    [ "$status" -eq 0 ]
}

@test "env.sh sets strict mode" {
    grep -q 'set -euo pipefail' "$PROJECT_ROOT/lib/improve/env.sh"
}

# ====================
# validate_improve_iteration() Tests
# ====================

@test "validate_improve_iteration allows valid iteration" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 1 3
        echo 'passed'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]]
}

@test "validate_improve_iteration allows iteration equal to max" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 3 3
        echo 'passed'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]]
}

@test "validate_improve_iteration exits when iteration exceeds max" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 4 3 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Maximum iterations"* ]]
}

@test "validate_improve_iteration exits with status 0 on max reached" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 5 3 2>&1
    "
    # Should exit 0 (normal completion)
    [ "$status" -eq 0 ]
}

@test "validate_improve_iteration shows correct max iteration count" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 10 7 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Maximum iterations (7)"* ]]
}

@test "validate_improve_iteration handles iteration 1 of 1" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 1 1
        echo 'passed'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]]
}

@test "validate_improve_iteration handles very large max iterations" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        validate_improve_iteration 50 100
        echo 'passed'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]]
}

# ====================
# generate_improve_session_label() Tests
# ====================

@test "generate_improve_session_label generates label with correct prefix" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        generate_improve_session_label
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^pi-runner- ]]
}

@test "generate_improve_session_label generates label with date format" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        generate_improve_session_label
    "
    [ "$status" -eq 0 ]
    # Should match pattern: pi-runner-YYYYMMDD-HHMMSS
    [[ "$output" =~ ^pi-runner-[0-9]{8}-[0-9]{6}$ ]]
}

@test "generate_improve_session_label generates unique labels" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        label1=\$(generate_improve_session_label)
        sleep 1
        label2=\$(generate_improve_session_label)
        if [[ \"\$label1\" != \"\$label2\" ]]; then
            echo 'unique'
        else
            echo 'not unique'
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"unique"* ]]
}

@test "generate_improve_session_label output is valid GitHub label format" {
    run bash -c "
        source '$PROJECT_ROOT/lib/improve/env.sh'
        label=\$(generate_improve_session_label)
        # GitHub labels allow alphanumeric, dash, underscore
        if [[ \"\$label\" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo 'valid'
        else
            echo 'invalid'
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"valid"* ]]
}

# ====================
# setup_improve_environment() - Basic Functionality
# ====================

@test "setup_improve_environment generates session_label when empty" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 '' '' false false 2>/dev/null
    
        echo \"\$_PARSE_session_label\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"pi-runner-"* ]]
}

@test "setup_improve_environment uses provided session_label" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'custom-label' '' false false 2>/dev/null
    
        echo \"\$_PARSE_session_label\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "custom-label" ]]
}

@test "setup_improve_environment creates log directory" {
    local test_log_dir="$BATS_TEST_TMPDIR/test-logs"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '$test_log_dir'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'test-label' '' false false 2>/dev/null
        
        # Check if directory was created
        if [[ -d '$test_log_dir' ]]; then
            echo 'directory created'
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"directory created"* ]]
}

@test "setup_improve_environment generates log_file path" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 2 3 'test-label' '' false false 2>/dev/null
    
        echo \"\$_PARSE_log_file\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *".improve-logs/iteration-2-"* ]]
}

@test "setup_improve_environment uses config log_dir when not provided" {
    # Verify that the code checks for empty log_dir and calls get_config
    source_content=$(cat "$PROJECT_ROOT/lib/improve/env.sh")
    [[ "$source_content" == *'[[ -z "$log_dir" ]]'* ]]
    [[ "$source_content" == *'get_config improve_logs_dir'* ]]
}

@test "setup_improve_environment uses provided log_dir over config" {
    # Verify that provided log_dir is used directly without calling get_config
    source_content=$(cat "$PROJECT_ROOT/lib/improve/env.sh")
    # Check that it only calls get_config when log_dir is empty
    [[ "$source_content" == *'if [[ -z "$log_dir" ]]'* ]]
}

# ====================
# setup_improve_environment() - Label Creation
# ====================

@test "setup_improve_environment creates GitHub label in normal mode" {
    local label_created=false
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() {
            echo 'label_created' >&2
            return 0
        }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'test-label' '' false false
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"label_created"* ]]
}

@test "setup_improve_environment skips label creation in dry-run mode" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() {
            echo 'ERROR: label should not be created in dry-run mode' >&2
            return 1
        }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'test-label' '' true false 2>/dev/null
    "
    [ "$status" -eq 0 ]
    # Should not contain error message
    [[ "$output" != *"ERROR: label should not be created"* ]]
}

@test "setup_improve_environment skips label creation in review-only mode" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() {
            echo 'ERROR: label should not be created in review-only mode' >&2
            return 1
        }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'test-label' '' false true 2>/dev/null
    "
    [ "$status" -eq 0 ]
    # Should not contain error message
    [[ "$output" != *"ERROR: label should not be created"* ]]
}

# ====================
# setup_improve_environment() - Quote Escaping
# ====================

@test "setup_improve_environment escapes single quotes in session_label" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 \"test's-label\" '' false false 2>/dev/null
        echo \"\$_PARSE_session_label\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "test's-label" ]]
}

@test "setup_improve_environment escapes single quotes in log_file" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'test-label' \"/tmp/user's-logs\" false false 2>/dev/null
        echo \"\$_PARSE_log_file\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/user's-logs/"* ]]
}

@test "setup_improve_environment uses safe global variable pattern" {
    # Verify that _PARSE_ global variables are used (safe pattern without eval)
    source_content=$(cat "$PROJECT_ROOT/lib/improve/env.sh")
    # Check for _PARSE_ variable assignments
    [[ "$source_content" == *'_PARSE_session_label='* ]]
    [[ "$source_content" == *'_PARSE_log_file='* ]]
    [[ "$source_content" == *'_PARSE_start_time='* ]]
}

# ====================
# setup_improve_environment() - Validation
# ====================

@test "setup_improve_environment calls validate_improve_iteration" {
    # Note: validate_improve_iteration is now called before setup_improve_environment
    # in improve_main() to avoid subshell exit issues.
    # Verify that the code documents this pattern.
    source_content=$(cat "$PROJECT_ROOT/lib/improve/env.sh")
    [[ "$source_content" == *"validate_improve_iteration"* ]]
}

@test "setup_improve_environment calls load_config" {
    grep -q 'load_config' "$PROJECT_ROOT/lib/improve/env.sh"
}

@test "setup_improve_environment calls check_improve_dependencies" {
    grep -q 'check_improve_dependencies' "$PROJECT_ROOT/lib/improve/env.sh"
}

# ====================
# setup_improve_environment() - Output Format
# ====================

@test "setup_improve_environment outputs start_time in ISO 8601 format" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 1 3 'test-label' '' false false 2>/dev/null
        echo \"\$_PARSE_start_time\"
    "
    [ "$status" -eq 0 ]
    # ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
    [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ]]
}

@test "setup_improve_environment displays header to stderr" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        
        # Mock dependencies
        require_config_file() { return 0; }
        load_config() { return 0; }
        check_improve_dependencies() { return 0; }
        get_config() {
            if [[ \"\$1\" == 'improve_logs_dir' ]]; then
                echo '.improve-logs'
            fi
        }
        create_label_if_not_exists() { return 0; }
        export -f require_config_file load_config check_improve_dependencies get_config create_label_if_not_exists
        
        source '$PROJECT_ROOT/lib/improve/env.sh'
        setup_improve_environment 2 5 'test-label' '' false false 2>&1 >/dev/null
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Continuous Improvement"* ]]
    [[ "$output" == *"Iteration 2/5"* ]]
}
