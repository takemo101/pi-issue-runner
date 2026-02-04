#!/usr/bin/env bats
# test/scripts/verify-config-docs.bats - verify-config-docs.shのテスト

load '../test_helper'

# 検証スクリプトのパス
VERIFY_SCRIPT="$PROJECT_ROOT/scripts/verify-config-docs.sh"

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
    [[ "$output" == *"lib/config.sh: 25 items"* ]]
    [[ "$output" == *"docs/configuration.md: 25 items"* ]]
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
    # 一時的にconfig.shを変更してテスト
    local temp_config="$BATS_TEST_TMPDIR/config.sh"
    cp "$PROJECT_ROOT/lib/config.sh" "$temp_config"
    echo 'CONFIG_NEW_SETTING="${CONFIG_NEW_SETTING:-.default}"' >> "$temp_config"
    
    # 元のconfig.shを一時的に置き換え
    mv "$PROJECT_ROOT/lib/config.sh" "$PROJECT_ROOT/lib/config.sh.bak"
    cp "$temp_config" "$PROJECT_ROOT/lib/config.sh"
    
    run "$VERIFY_SCRIPT"
    local result=$status
    
    # 元に戻す
    mv "$PROJECT_ROOT/lib/config.sh.bak" "$PROJECT_ROOT/lib/config.sh"
    
    # 検証
    [ "$result" -eq 1 ]
    [[ "$output" == *"Configuration mismatch detected"* ]]
}
