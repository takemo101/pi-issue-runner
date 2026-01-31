#!/usr/bin/env bats
# log.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ログ出力テスト
# ====================

@test "log_info outputs message" {
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_info "Test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test message"* ]]
}

@test "log_info includes INFO tag" {
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_info "Test message"
    [[ "$output" == *"INFO"* ]] || [[ "$output" == *"ℹ"* ]]
}

@test "log_warn outputs warning message" {
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_warn "Warning message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning message"* ]]
}

@test "log_error outputs error message" {
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_error "Error message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error message"* ]]
}

# Note: log_success does not exist in lib/log.sh

# ====================
# デバッグログテスト
# ====================

@test "log_debug outputs nothing when DEBUG is not set" {
    unset DEBUG
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_debug "Debug message"
    [ -z "$output" ] || [[ "$output" != *"Debug message"* ]]
}

@test "log_debug outputs message when DEBUG=1" {
    export DEBUG=1
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_debug "Debug message"
    [[ "$output" == *"Debug message"* ]]
    
    unset DEBUG
}

# ====================
# 色付き出力テスト
# ====================

@test "log functions work without TERM" {
    unset TERM
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_info "No TERM test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No TERM test"* ]]
}

# ====================
# 複数行ログテスト
# ====================

@test "log_info handles multiline messages" {
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_info "Line 1
Line 2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Line 1"* ]]
}

# ====================
# 特殊文字テスト
# ====================

@test "log_info handles special characters" {
    source "$PROJECT_ROOT/lib/log.sh"
    
    run log_info "Special: \$PATH and 'quotes'"
    [ "$status" -eq 0 ]
}
