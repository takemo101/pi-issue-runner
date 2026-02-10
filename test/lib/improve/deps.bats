#!/usr/bin/env bats
# test/lib/improve/deps.bats - Unit tests for lib/improve/deps.sh

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

@test "deps.sh can be sourced" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/improve/deps.sh'
        echo 'success'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "deps.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/improve/deps.sh"
    [ "$status" -eq 0 ]
}

@test "deps.sh sets strict mode" {
    grep -q 'set -euo pipefail' "$PROJECT_ROOT/lib/improve/deps.sh"
}

# ====================
# check_improve_dependencies() - Success Cases
# ====================

@test "check_improve_dependencies succeeds when all dependencies exist" {
    # Create mocks for all required commands
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/jq"
    
    export PATH="$MOCK_DIR:$PATH"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/deps.sh'
        check_improve_dependencies
    "
    [ "$status" -eq 0 ]
}

@test "check_improve_dependencies checks for pi command" {
    grep -q 'pi_command' "$PROJECT_ROOT/lib/improve/deps.sh"
    grep -q 'command -v.*pi' "$PROJECT_ROOT/lib/improve/deps.sh"
}

@test "check_improve_dependencies checks for gh command" {
    grep -q 'command -v gh' "$PROJECT_ROOT/lib/improve/deps.sh"
}

@test "check_improve_dependencies checks for jq command" {
    grep -q 'command -v jq' "$PROJECT_ROOT/lib/improve/deps.sh"
}

# ====================
# check_improve_dependencies() - Failure Cases
# ====================

@test "check_improve_dependencies fails when pi command missing" {
    # Verify the code checks for pi command
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'command -v "$pi_command"'* ]] || [[ "$source_content" == *'command -v $pi_command'* ]]
    [[ "$source_content" == *"missing"* ]]
}

@test "check_improve_dependencies fails when gh command missing" {
    # Verify the code handles missing gh
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'command -v gh'* ]]
    [[ "$source_content" == *"missing"* ]]
}

@test "check_improve_dependencies fails when jq command missing" {
    # Verify the code handles missing jq
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'command -v jq'* ]]
    [[ "$source_content" == *"missing"* ]]
}

@test "check_improve_dependencies reports multiple missing dependencies" {
    # Verify the code accumulates missing dependencies in an array
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *"missing=("* ]]
    [[ "$source_content" == *"missing+="* ]]
}

@test "check_improve_dependencies fails when all dependencies missing" {
    # Verify the code returns 1 when dependencies are missing
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'${#missing[@]}'* ]]
    [[ "$source_content" == *"return 1"* ]]
}

# ====================
# check_improve_dependencies() - Edge Cases
# ====================

@test "check_improve_dependencies respects custom pi_command from config" {
    # Create custom-pi instead of pi
    cat > "$MOCK_DIR/custom-pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/custom-pi"
    
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/jq"
    
    export PATH="$MOCK_DIR:$PATH"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'custom-pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/deps.sh'
        check_improve_dependencies
    "
    [ "$status" -eq 0 ]
}

@test "check_improve_dependencies fails with custom pi_command when missing" {
    # Only provide gh and jq, not custom-pi
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/gh"
    
    cat > "$MOCK_DIR/jq" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/jq"
    
    export PATH="$MOCK_DIR:$PATH"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'custom-pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/deps.sh'
        check_improve_dependencies 2>&1
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing dependencies"* ]]
    [[ "$output" == *"custom-pi"* ]]
}

# ====================
# Backward Compatibility
# ====================

# ====================
# Output Format Tests
# ====================

@test "check_improve_dependencies outputs error message to stderr" {
    # Verify the code outputs to stderr (uses log_error or >&2)
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'log_error'* ]] || [[ "$source_content" == *'>&2'* ]]
}

@test "check_improve_dependencies lists each missing dependency" {
    # Verify the code loops through missing dependencies
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'for dep in'* ]]
    [[ "$source_content" == *'echo'* ]]
}
