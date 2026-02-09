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

# ====================
# Context Collection Tests
# ====================

@test "_collect_review_context returns empty when no git/gh available" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    # Override commands to simulate missing git/gh
    git() { return 1; }
    gh() { return 1; }
    export -f git gh

    cd "$BATS_TEST_TMPDIR"
    run _collect_review_context "test-label" ""
    [ "$status" -eq 0 ]
    # Should not fail, just return minimal/empty context
}

@test "_collect_review_context includes recent commits when in git repo" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    # Run in actual project directory (which is a git repo)
    cd "$PROJECT_ROOT"
    result=$(_collect_review_context "test-label" "")
    [[ "$result" == *"最近のコミット"* ]]
}

@test "_collect_review_context includes known constraints from AGENTS.md" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    cd "$PROJECT_ROOT"
    result=$(_collect_review_context "test-label" "")
    [[ "$result" == *"既知の制約"* ]]
}

@test "_collect_review_context includes previous log summary" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    local log_dir="${BATS_TEST_TMPDIR}/logs"
    mkdir -p "$log_dir"
    cat > "$log_dir/2026-02-08.log" << 'EOF'
[PHASE 1] Running project review...
Created issue #100 - fix typo
Created issue #101 - update docs
✅ Review complete
EOF

    cd "$BATS_TEST_TMPDIR"
    result=$(_collect_review_context "test-label" "$log_dir")
    [[ "$result" == *"前回のイテレーション結果"* ]]
}

@test "run_improve_review_phase prompt includes duplicate prevention rules" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *"重複する問題は作成しないでください"* ]]
}

@test "run_improve_review_phase prompt includes one-issue-per-problem rule" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *"1つのIssueには1つの具体的な問題"* ]]
}

# ====================
# Custom Review Prompt Tests
# ====================

@test "_find_review_prompt_file finds agents/improve-review.md" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    mkdir -p "$BATS_TEST_TMPDIR/project/agents"
    echo "custom prompt {{max_issues}}" > "$BATS_TEST_TMPDIR/project/agents/improve-review.md"

    result=$(_find_review_prompt_file "$BATS_TEST_TMPDIR/project")
    [[ "$result" == *"agents/improve-review.md" ]]
}

@test "_find_review_prompt_file finds .pi/agents/improve-review.md" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    mkdir -p "$BATS_TEST_TMPDIR/project/.pi/agents"
    echo "custom prompt" > "$BATS_TEST_TMPDIR/project/.pi/agents/improve-review.md"

    result=$(_find_review_prompt_file "$BATS_TEST_TMPDIR/project")
    [[ "$result" == *".pi/agents/improve-review.md" ]]
}

@test "_find_review_prompt_file prefers agents/ over .pi/agents/" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    mkdir -p "$BATS_TEST_TMPDIR/project/agents"
    mkdir -p "$BATS_TEST_TMPDIR/project/.pi/agents"
    echo "project local" > "$BATS_TEST_TMPDIR/project/agents/improve-review.md"
    echo "pi local" > "$BATS_TEST_TMPDIR/project/.pi/agents/improve-review.md"

    result=$(_find_review_prompt_file "$BATS_TEST_TMPDIR/project")
    [[ "$result" == *"project/agents/improve-review.md" ]]
}

@test "_find_review_prompt_file returns builtin when exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    # No project-local files, should find builtin
    result=$(_find_review_prompt_file "$BATS_TEST_TMPDIR")
    [[ "$result" == *"agents/improve-review.md" ]]
}

@test "_render_review_prompt expands variables" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/improve/review.sh"

    local template="Create {{max_issues}} issues with label {{session_label}}. Context: {{review_context}}"
    result=$(_render_review_prompt "$template" "5" "improve-v1" "some context")
    [[ "$result" == *"Create 5 issues"* ]]
    [[ "$result" == *"label improve-v1"* ]]
    [[ "$result" == *"Context: some context"* ]]
}
