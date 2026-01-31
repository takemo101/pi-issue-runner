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

# ====================
# ログレベルテスト
# ====================

@test "log_debug hidden when LOG_LEVEL is INFO" {
    source "$PROJECT_ROOT/lib/log.sh"
    LOG_LEVEL="INFO"
    
    run log_debug "Debug message"
    [ -z "$output" ]
}

@test "log_debug shown when LOG_LEVEL is DEBUG" {
    source "$PROJECT_ROOT/lib/log.sh"
    LOG_LEVEL="DEBUG"
    
    run log_debug "Debug message"
    [[ "$output" == *"DEBUG"* ]] || [[ "$output" == *"Debug message"* ]]
}

@test "log_info hidden when LOG_LEVEL is ERROR" {
    source "$PROJECT_ROOT/lib/log.sh"
    LOG_LEVEL="ERROR"
    
    run log_info "Info message"
    [ -z "$output" ]
}

@test "log_error shown when LOG_LEVEL is ERROR" {
    source "$PROJECT_ROOT/lib/log.sh"
    LOG_LEVEL="ERROR"
    
    run log_error "Error message"
    [[ "$output" == *"Error message"* ]]
}

# ====================
# set_log_level テスト
# ====================

@test "set_log_level sets DEBUG level" {
    source "$PROJECT_ROOT/lib/log.sh"
    set_log_level "DEBUG"
    [ "$LOG_LEVEL" = "DEBUG" ]
}

@test "set_log_level sets WARN level" {
    source "$PROJECT_ROOT/lib/log.sh"
    set_log_level "WARN"
    [ "$LOG_LEVEL" = "WARN" ]
}

@test "set_log_level defaults to INFO for invalid level" {
    source "$PROJECT_ROOT/lib/log.sh"
    set_log_level "INVALID" 2>/dev/null
    [ "$LOG_LEVEL" = "INFO" ]
}

# ====================
# enable_verbose/quiet テスト
# ====================

@test "enable_verbose sets LOG_LEVEL to DEBUG" {
    source "$PROJECT_ROOT/lib/log.sh"
    enable_verbose
    [ "$LOG_LEVEL" = "DEBUG" ]
}

@test "enable_quiet sets LOG_LEVEL to ERROR" {
    source "$PROJECT_ROOT/lib/log.sh"
    enable_quiet
    [ "$LOG_LEVEL" = "ERROR" ]
}

# ====================
# 関数存在テスト
# ====================

@test "log function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f log > /dev/null
}

@test "log_debug function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f log_debug > /dev/null
}

@test "log_info function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f log_info > /dev/null
}

@test "log_warn function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f log_warn > /dev/null
}

@test "log_error function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f log_error > /dev/null
}

@test "set_log_level function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f set_log_level > /dev/null
}

@test "enable_verbose function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f enable_verbose > /dev/null
}

@test "enable_quiet function exists" {
    source "$PROJECT_ROOT/lib/log.sh"
    declare -f enable_quiet > /dev/null
}
