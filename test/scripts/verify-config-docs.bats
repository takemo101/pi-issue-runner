#!/usr/bin/env bats
# test/scripts/verify-config-docs.bats - verify-config-docs.shのテスト

load '../test_helper'

# 検証スクリプトのパス
VERIFY_SCRIPT="$PROJECT_ROOT/scripts/verify-config-docs.sh"

setup() {
    # 設定状態をリセット（テスト間の汚染防止）
    reset_config_state
}

@test "verify-config-docs.sh exists and is executable" {
    [ -f "$VERIFY_SCRIPT" ]
    [ -x "$VERIFY_SCRIPT" ]
}

@test "verify-config-docs.sh shows help" {
    run "$VERIFY_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Verify consistency"* ]]
}

@test "verify-config-docs.sh succeeds with current configuration" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All configuration items are documented"* ]]
    [[ "$output" == *"Configuration documentation is up-to-date"* ]]
}

@test "verify-config-docs.sh counts configuration items correctly" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib/config.sh: 44 items"* ]]
    [[ "$output" == *"docs/configuration.md: 44 items"* ]]
}

@test "verify-config-docs.sh checks default values" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONFIG_WORKTREE_BASE_DIR"* ]]
    [[ "$output" == *"CONFIG_MULTIPLEXER_SESSION_PREFIX"* ]]
    [[ "$output" == *"CONFIG_PARALLEL_MAX_CONCURRENT"* ]]
    [[ "$output" == *"CONFIG_PLANS_KEEP_RECENT"* ]]
}

@test "verify-config-docs.sh checks document structure" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Section "worktree" found'* ]]
    [[ "$output" == *'Section "multiplexer" found'* ]]
    [[ "$output" == *'Section "pi" found'* ]]
    [[ "$output" == *'Section "agent" found'* ]]
}

@test "verify-config-docs.sh handles invalid option" {
    run "$VERIFY_SCRIPT" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "verify-config-docs.sh detects missing documentation (simulated)" {
    # Create isolated test environment to avoid interfering with parallel tests
    local test_root="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$test_root/lib" "$test_root/docs" "$test_root/scripts"
    
    # Copy necessary files
    cp "$PROJECT_ROOT/lib/log.sh" "$test_root/lib/"
    cp "$PROJECT_ROOT/scripts/verify-config-docs.sh" "$test_root/scripts/"
    cp "$PROJECT_ROOT/docs/configuration.md" "$test_root/docs/"
    cp "$PROJECT_ROOT/docs/hooks.md" "$test_root/docs/"
    
    # Copy config.sh and add a new setting to simulate missing documentation
    cp "$PROJECT_ROOT/lib/config.sh" "$test_root/lib/config.sh"
    echo 'CONFIG_NEW_SETTING="${CONFIG_NEW_SETTING:-.default}"' >> "$test_root/lib/config.sh"
    
    # Run the script in the isolated environment
    run bash -c "cd '$test_root' && PROJECT_ROOT='$test_root' bash '$test_root/scripts/verify-config-docs.sh'"
    
    # Verify the script detects missing documentation
    [ "$status" -eq 1 ]
    [[ "$output" == *"Configuration mismatch detected"* ]]
}

@test "verify-config-docs.sh checks hooks documentation exists" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking hooks configuration"* ]]
    [[ "$output" =~ (docs/hooks\.md exists|hooks section exists) ]]
}

@test "verify-config-docs.sh verifies hook events are documented" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Hook event "on_start" is documented'* ]]
    [[ "$output" == *'Hook event "on_success" is documented'* ]]
    [[ "$output" == *'Hook event "on_error" is documented'* ]]
    [[ "$output" == *'Hook event "on_cleanup" is documented'* ]]
    [[ "$output" == *'Hook event "on_improve_start" is documented'* ]]
    [[ "$output" == *'Hook event "on_improve_end" is documented'* ]]
    [[ "$output" == *'Hook event "on_iteration_start" is documented'* ]]
    [[ "$output" == *'Hook event "on_iteration_end" is documented'* ]]
    [[ "$output" == *'Hook event "on_review_complete" is documented'* ]]
}

@test "verify-config-docs.sh checks hooks configuration example" {
    run "$VERIFY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks configuration example found"* ]]
}

@test "verify-config-docs.sh detects missing hooks documentation" {
    # Create isolated test environment to avoid interfering with parallel tests
    local test_root="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$test_root/lib" "$test_root/docs" "$test_root/scripts"
    
    # Copy necessary files for the script to run
    cp "$PROJECT_ROOT/lib/config.sh" "$test_root/lib/"
    cp "$PROJECT_ROOT/lib/log.sh" "$test_root/lib/"
    cp "$PROJECT_ROOT/scripts/verify-config-docs.sh" "$test_root/scripts/"
    
    # Copy configuration.md but remove the hooks section to simulate missing documentation
    awk '/^### hooks$/,/^### / { if (/^### hooks$/) next; if (/^### / && !/^### hooks$/) print; next } 1' \
        "$PROJECT_ROOT/docs/configuration.md" > "$test_root/docs/configuration.md"
    
    # Intentionally do NOT copy docs/hooks.md to simulate missing file
    
    # Run the script in the isolated environment (use absolute path, avoid cd)
    run bash -c "cd '$test_root' && PROJECT_ROOT='$test_root' bash '$test_root/scripts/verify-config-docs.sh'"
    
    # Verify the script detects missing hooks documentation
    [ "$status" -eq 1 ]
    [[ "$output" == *"Neither docs/hooks.md nor hooks section"* ]]
}
