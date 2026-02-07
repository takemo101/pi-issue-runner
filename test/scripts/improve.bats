#!/usr/bin/env bats
# improve.sh のBatsテスト (2段階方式)

load '../test_helper'

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
# ヘルプオプションテスト
# ====================

@test "improve.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
}

@test "improve.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "improve.sh --help shows --max-iterations option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--max-iterations"* ]]
}

@test "improve.sh --help shows --max-issues option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--max-issues"* ]]
}

@test "improve.sh --help shows --timeout option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--timeout"* ]]
}

@test "improve.sh --help shows --verbose option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--verbose"* ]]
}

@test "improve.sh --help shows --log-dir option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--log-dir"* ]]
}

@test "improve.sh --help shows --dry-run option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--dry-run"* ]]
}

@test "improve.sh --help shows --review-only option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--review-only"* ]]
}

@test "improve.sh --help shows --auto-continue option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--auto-continue"* ]]
}

@test "improve.sh --help shows --label option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--label"* ]]
}

@test "improve.sh --help shows description" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Description:"* ]]
}

@test "improve.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Examples:"* ]]
}

@test "improve.sh --help shows log file information" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Log files:"* ]]
}

@test "improve.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/improve.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# オプションパーステスト
# ====================

@test "improve.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/improve.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "improve.sh with unexpected argument fails" {
    run "$PROJECT_ROOT/scripts/improve.sh" unexpected-arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

# ====================
# スクリプト構造テスト
# ====================

@test "improve.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/improve.sh"
    [ "$status" -eq 0 ]
}

@test "improve.sh sources lib/improve.sh" {
    grep -q "lib/improve.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh calls improve_main function" {
    grep -q "improve_main" "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# CLI機能テスト（実装はlib/improve.shにある）
# ====================

@test "improve.sh can be executed" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
}

# ====================
# Configuration Integration Tests
# ====================

@test "improve.sh respects improve_logs_dir config" {
    # Create a test project directory
    local test_project="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$test_project"
    cd "$test_project"
    
    # Create a test config with custom log directory
    cat > "$test_project/.pi-runner.yaml" << 'EOF'
improve_logs:
  dir: custom-improve-logs
EOF
    
    # Verify config can be parsed (basic smoke test)
    run bash -c "source '$PROJECT_ROOT/lib/config.sh' && load_config '$test_project/.pi-runner.yaml' && get_config improve_logs_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == "custom-improve-logs" ]]
}

# ====================
# Sweep Integration Tests (Issue #1052)
# ====================

@test "lib/improve.sh defines _IMPROVE_SCRIPT_DIR for sweep.sh calls" {
    # Verify that _IMPROVE_SCRIPT_DIR is defined in lib/improve.sh
    grep -q "_IMPROVE_SCRIPT_DIR=" "$PROJECT_ROOT/lib/improve.sh"
}

@test "lib/improve.sh calls sweep.sh after wait_for_improve_completion" {
    # Verify sweep.sh is called in the improve_main function
    # Check that it appears after wait_for_improve_completion
    local improve_main_section
    improve_main_section=$(sed -n '/^improve_main()/,/^}/p' "$PROJECT_ROOT/lib/improve.sh")
    
    # Verify sweep.sh call exists
    echo "$improve_main_section" | grep -q "sweep.sh"
    
    # Verify --force flag is used
    echo "$improve_main_section" | grep -q "sweep.sh.*--force"
}

@test "lib/improve.sh sweep.sh call uses --force flag" {
    # Verify --force flag is passed to sweep.sh
    grep -q 'sweep.sh.*--force' "$PROJECT_ROOT/lib/improve.sh"
}

@test "lib/improve.sh sweep.sh call is non-fatal" {
    # Verify that sweep.sh failure doesn't stop execution
    # This is done by using 'if !' pattern or '|| true'
    local improve_sh_content
    improve_sh_content=$(<"$PROJECT_ROOT/lib/improve.sh")
    
    # Check for non-fatal pattern (if ! ... then ... fi)
    if echo "$improve_sh_content" | grep -q 'if.*sweep\.sh.*then'; then
        # Pattern found: if ! sweep.sh; then log_warn; fi
        return 0
    fi
    
    # Alternative pattern: sweep.sh || true
    if echo "$improve_sh_content" | grep -q 'sweep\.sh.*||.*true'; then
        return 0
    fi
    
    # If neither pattern found, test should fail
    return 1
}

@test "lib/improve.sh sweep.sh is called between Phase 4 and Phase 5" {
    # Verify ordering: wait_for_improve_completion -> sweep.sh -> start_improve_next_iteration
    local improve_main
    improve_main=$(sed -n '/^improve_main()/,/^}/p' "$PROJECT_ROOT/lib/improve.sh")
    
    # Extract line numbers for each call
    local wait_line sweep_line next_line
    wait_line=$(echo "$improve_main" | grep -n "wait_for_improve_completion" | cut -d: -f1)
    sweep_line=$(echo "$improve_main" | grep -n "sweep.sh" | cut -d: -f1)
    next_line=$(echo "$improve_main" | grep -n "start_improve_next_iteration" | cut -d: -f1)
    
    # Verify ordering: wait < sweep < next
    [[ "$wait_line" -lt "$sweep_line" ]]
    [[ "$sweep_line" -lt "$next_line" ]]
}

# ====================
# Note: Implementation details have been moved to lib/improve.sh
# and are tested in test/lib/improve.bats
# ====================
