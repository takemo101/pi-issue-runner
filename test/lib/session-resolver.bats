#!/usr/bin/env bats
# ============================================================================
# test/lib/session-resolver.bats - Tests for session-resolver.sh
# ============================================================================

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset _MUX_TYPE
    unset PI_RUNNER_MULTIPLEXER_SESSION_PREFIX
    unset PI_RUNNER_SESSION_PREFIX
    
    # テストでは tmux を使用
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
}

teardown() {
    unset PI_RUNNER_MULTIPLEXER_SESSION_PREFIX
    unset PI_RUNNER_SESSION_PREFIX
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ============================================================================
# resolve_session_target tests
# ============================================================================

@test "resolve_session_target: resolves issue number to session name" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "42")
    
    # Should output: "42<TAB>pi-issue-42"
    [[ "$result" == "42"$'\t'"pi-issue-42" ]]
}

@test "resolve_session_target: resolves session name to issue number" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "pi-issue-42")
    
    # Should output: "42<TAB>pi-issue-42"
    [[ "$result" == "42"$'\t'"pi-issue-42" ]]
}

@test "resolve_session_target: handles multi-digit issue numbers" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "1234")
    
    [[ "$result" == "1234"$'\t'"pi-issue-1234" ]]
}

@test "resolve_session_target: handles custom session prefix" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    # Override session prefix
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="custom"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "99")
    
    [[ "$result" == "99"$'\t'"custom-issue-99" ]]
}

@test "resolve_session_target: can be parsed with IFS read" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local issue_number session_name
    IFS=$'\t' read -r issue_number session_name < <(resolve_session_target "42")
    
    [[ "$issue_number" == "42" ]]
    [[ "$session_name" == "pi-issue-42" ]]
}

@test "resolve_session_target: returns error for empty input" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    run resolve_session_target ""
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"target is required"* ]]
}

@test "resolve_session_target: handles session name with hyphens" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "pi-issue-42-test")
    
    # Should extract "42" from the session name
    [[ "$result" == "42"$'\t'"pi-issue-42-test" ]]
}

@test "resolve_session_target: integration with real scripts workflow" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    # Test both input types
    local issue_number1 session_name1
    IFS=$'\t' read -r issue_number1 session_name1 < <(resolve_session_target "42")
    
    local issue_number2 session_name2
    IFS=$'\t' read -r issue_number2 session_name2 < <(resolve_session_target "$session_name1")
    
    # Both should resolve to the same values
    [[ "$issue_number1" == "$issue_number2" ]]
    [[ "$session_name1" == "$session_name2" ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "resolve_session_target: handles single digit issue number" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "1")
    
    [[ "$result" == "1"$'\t'"pi-issue-1" ]]
}

@test "resolve_session_target: handles very large issue numbers" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    local result
    result=$(resolve_session_target "999999")
    
    [[ "$result" == "999999"$'\t'"pi-issue-999999" ]]
}

@test "resolve_session_target: distinguishes numbers from session names" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/session-resolver.sh"
    
    _CONFIG_LOADED=""
    CONFIG_MULTIPLEXER_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    # Pure number -> treat as issue number
    local result1
    result1=$(resolve_session_target "123")
    [[ "$result1" == "123"$'\t'"pi-issue-123" ]]
    
    # Session name containing numbers -> treat as session name
    local result2
    result2=$(resolve_session_target "pi-issue-123")
    [[ "$result2" == "123"$'\t'"pi-issue-123" ]]
}
