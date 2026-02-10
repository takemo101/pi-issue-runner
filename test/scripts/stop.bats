#!/usr/bin/env bats
# stop.sh のBatsテスト

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

@test "stop.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [ "$status" -eq 0 ]
}

@test "stop.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "stop.sh --help shows session-name argument" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "stop.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"Examples:"* ]]
}

@test "stop.sh --help shows pi-issue-42 example" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"pi-issue-42"* ]] || [[ "$output" == *"42"* ]]
}

@test "stop.sh --help shows --cleanup option" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"--cleanup"* ]]
}

@test "stop.sh --help shows --close-issue option" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"--close-issue"* ]]
}

@test "stop.sh --help shows --force option" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"--force"* ]]
}

@test "stop.sh --help shows --delete-branch option" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [[ "$output" == *"--delete-branch"* ]]
}

@test "stop.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/stop.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# エラーケーステスト
# ====================

@test "stop.sh without argument fails" {
    run "$PROJECT_ROOT/scripts/stop.sh"
    [ "$status" -ne 0 ]
}

@test "stop.sh without argument shows error message" {
    run "$PROJECT_ROOT/scripts/stop.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "stop.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/stop.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown"* ]]
}

# ====================
# スクリプト構造テスト
# ====================

@test "stop.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/stop.sh"
    [ "$status" -eq 0 ]
}

@test "stop.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh sources tmux.sh" {
    grep -q "lib/tmux.sh" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh sources session-resolver.sh" {
    grep -q "session-resolver.sh" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh uses resolve_session_target" {
    grep -q "resolve_session_target" "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh calls kill_session" {
    grep -q "kill_session" "$PROJECT_ROOT/scripts/stop.sh"
}

# ====================
# セッション名生成テスト
# ====================

@test "generate_session_name contains issue number for stop" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    load_config
    
    result="$(generate_session_name "42")"
    [[ "$result" == *"42"* ]]
}

@test "generate_session_name contains issue pattern for stop" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    load_config
    
    result="$(generate_session_name "999")"
    [[ "$result" == *"999"* ]]
}

# ====================
# セッション停止ロジックテスト
# ====================

@test "stop.sh calls kill_session with session_name" {
    grep -q 'kill_session "$session_name"' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh logs session stopped" {
    grep -q "Session stopped" "$PROJECT_ROOT/scripts/stop.sh" || grep -q "stopped" "$PROJECT_ROOT/scripts/stop.sh"
}

# ====================
# --cleanup オプションテスト
# ====================

@test "stop.sh has --cleanup option handling" {
    grep -q '\-\-cleanup' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --cleanup calls cleanup.sh" {
    grep -q 'cleanup.sh' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --cleanup records abandoned in tracker" {
    grep -q 'record_tracker_entry' "$PROJECT_ROOT/scripts/stop.sh"
    grep -q '"abandoned"' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --cleanup sets status to abandoned" {
    grep -q 'set_status.*abandoned' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --cleanup passes --keep-session to cleanup.sh" {
    grep -q '\-\-keep-session' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --cleanup passes --force to cleanup.sh when specified" {
    grep -q '\-\-force' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --cleanup passes --delete-branch to cleanup.sh when specified" {
    grep -q '\-\-delete-branch' "$PROJECT_ROOT/scripts/stop.sh"
}

# ====================
# --close-issue オプションテスト
# ====================

@test "stop.sh has --close-issue option handling" {
    grep -q '\-\-close-issue' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh --close-issue uses gh issue close" {
    grep -q 'gh issue close' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh sources tracker.sh for --cleanup" {
    grep -q 'lib/tracker.sh' "$PROJECT_ROOT/scripts/stop.sh"
}

@test "stop.sh sources status.sh for --cleanup" {
    grep -q 'lib/status.sh' "$PROJECT_ROOT/scripts/stop.sh"
}
