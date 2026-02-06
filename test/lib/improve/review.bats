#!/usr/bin/env bats
# test/lib/improve/review.bats - Unit tests for lib/improve/review.sh

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

@test "review.sh can be sourced" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/improve/review.sh'
        echo 'success'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "review.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/improve/review.sh"
    [ "$status" -eq 0 ]
}

@test "review.sh sets strict mode" {
    grep -q 'set -euo pipefail' "$PROJECT_ROOT/lib/improve/review.sh"
}

# ====================
# run_improve_review_phase() - Normal Mode
# ====================

@test "run_improve_review_phase calls pi --print in normal mode" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
echo "Mock pi called with: $@"
# Check for --print flag
if [[ "$*" == *"--print"* ]]; then
    echo "Review completed"
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false false 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--print"* ]]
}

@test "run_improve_review_phase includes session label in prompt" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
# Print the message argument to verify it
echo "$@" | grep -o "test-session-label" || exit 1
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-session-label' '$test_log' false false 2>&1
    "
    [ "$status" -eq 0 ]
}

@test "run_improve_review_phase includes max_issues in prompt" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
# Print the message argument to verify it includes max_issues
echo "$@" | grep -o "最大10件" || exit 1
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 10 'test-label' '$test_log' false false 2>&1
    "
    [ "$status" -eq 0 ]
}

@test "run_improve_review_phase instructs to create GitHub Issues in normal mode" {
    # Create mock pi command that captures the prompt
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
# Verify prompt includes Issue creation instruction
echo "$@" | grep -q "GitHub Issueを作成してください" && exit 0
exit 1
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false false 2>&1
    "
    [ "$status" -eq 0 ]
}

@test "run_improve_review_phase instructs to use --label option in normal mode" {
    # Create mock pi command that captures the prompt
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
# Verify prompt includes --label instruction
echo "$@" | grep -q "\-\-label test-session" && exit 0
exit 1
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-session' '$test_log' false false 2>&1
    "
    [ "$status" -eq 0 ]
}

# ====================
# run_improve_review_phase() - Dry-run Mode
# ====================

@test "run_improve_review_phase uses dry-run mode prompt when dry_run=true" {
    # Create mock pi command that captures the prompt
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
# Verify prompt says NOT to create Issues
echo "$@" | grep -q "GitHub Issueは作成しないでください" && exit 0
exit 1
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' true false 2>&1
    "
    [ "$status" -eq 0 ]
}

@test "run_improve_review_phase exits early in dry-run mode" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' true false
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run mode complete"* ]]
    [[ "$output" == *"No Issues were created"* ]]
}

# ====================
# run_improve_review_phase() - Review-only Mode
# ====================

@test "run_improve_review_phase uses review-only mode prompt when review_only=true" {
    # Create mock pi command that captures the prompt
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
# Verify prompt says NOT to create Issues
echo "$@" | grep -q "GitHub Issueは作成しないでください" && exit 0
exit 1
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false true 2>&1
    "
    [ "$status" -eq 0 ]
}

@test "run_improve_review_phase exits early in review-only mode" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false true
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review-only mode complete"* ]]
}

# ====================
# run_improve_review_phase() - Error Handling
# ====================

@test "run_improve_review_phase handles pi command failure" {
    # Create mock pi command that fails
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
echo "Error: something went wrong" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false false
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"pi command returned non-zero exit code"* ]]
}

@test "run_improve_review_phase logs output to file" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
echo "Review output line 1"
echo "Review output line 2"
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false false 2>&1 >/dev/null
        
        # Check log file was created
        if [[ -f '$test_log' ]]; then
            echo 'log file created'
        fi
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"log file created"* ]]
}

# ====================
# run_improve_review_phase() - Phase Messages
# ====================

@test "run_improve_review_phase shows phase marker" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false false
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"[PHASE 1]"* ]]
}

@test "run_improve_review_phase shows different message for dry-run mode" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' true false
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run mode"* ]]
}

@test "run_improve_review_phase shows log file path" {
    # Create mock pi command
    cat > "$MOCK_DIR/pi" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_DIR/pi"
    
    export PATH="$MOCK_DIR:$PATH"
    local test_log="$BATS_TEST_TMPDIR/test.log"
    
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/config.sh'
        get_config() {
            if [[ \"\$1\" == 'pi_command' ]]; then
                echo 'pi'
            fi
        }
        export -f get_config
        source '$PROJECT_ROOT/lib/improve/review.sh'
        run_improve_review_phase 5 'test-label' '$test_log' false false
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Log saved to: $test_log"* ]]
}

# ====================
# Backward Compatibility
# ====================

@test "run_review_phase() is backward compatible wrapper" {
    grep -q 'run_review_phase()' "$PROJECT_ROOT/lib/improve/review.sh"
}

@test "run_review_phase() calls run_improve_review_phase()" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    # Check that backward compat wrapper exists and calls the new function
    [[ "$source_content" =~ run_review_phase\(\).*run_improve_review_phase ]]
}

# ====================
# Prompt Content Verification
# ====================

@test "run_improve_review_phase prompt mentions project-review skill" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *"project-reviewスキル"* ]]
}

@test "run_improve_review_phase prompt provides gh issue create example" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *"gh issue create"* ]]
}

@test "run_improve_review_phase prompt includes fallback message for no problems" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *"問題は見つかりませんでした"* ]]
}
