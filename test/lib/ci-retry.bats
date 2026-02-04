#!/usr/bin/env bats
# ci-retry.bats - CI自動修正リトライ管理機能のテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 並列実行時の衝突を避けるため、テストごとに一意な状態ディレクトリを使用
    export PI_RUNNER_STATE_DIR="$BATS_TEST_TMPDIR/pi-runner-state"
    mkdir -p "$PI_RUNNER_STATE_DIR"
    
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/ci-retry.sh"
}

teardown() {
    # テストごとの状態ディレクトリは全体クリーンアップ時に削除される
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# 定数テスト
# ===================

@test "retry constants are defined correctly" {
    [[ "$MAX_RETRY_COUNT" == "3" ]]
}

@test "MAX_RETRY_COUNT is numeric and positive" {
    [[ "$MAX_RETRY_COUNT" =~ ^[0-9]+$ ]]
    [[ "$MAX_RETRY_COUNT" -gt 0 ]]
}

# ===================
# get_retry_state_file テスト
# ===================

@test "get_retry_state_file returns consistent path" {
    run get_retry_state_file 12345
    [ "$status" -eq 0 ]
    [[ "$output" == *"ci-retry-12345"* ]]
}

@test "get_retry_state_file creates state directory" {
    # カスタム状態ディレクトリを使用
    export PI_RUNNER_STATE_DIR="$BATS_TEST_TMPDIR/custom-state"
    
    run get_retry_state_file 12345
    [ "$status" -eq 0 ]
    
    # ディレクトリが作成されているか確認
    [ -d "$BATS_TEST_TMPDIR/custom-state" ]
}

# ===================
# get_retry_count テスト
# ===================

@test "get_retry_count returns 0 for new issue" {
    run get_retry_count 99999
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_retry_count returns 0 when state file doesn't exist" {
    # 確実に存在しないissue番号を使用
    run get_retry_count 999999999
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ===================
# increment_retry_count テスト
# ===================

@test "increment_retry_count increments correctly" {
    local issue_number=99999
    
    # 初期値は0
    run get_retry_count "$issue_number"
    [ "$output" = "0" ]
    
    # インクリメント
    increment_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "1" ]
    
    # さらにインクリメント
    increment_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "2" ]
}

@test "increment_retry_count works from 0 to 1" {
    local issue_number=99998
    
    run get_retry_count "$issue_number"
    [ "$output" = "0" ]
    
    increment_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "1" ]
}

# ===================
# reset_retry_count テスト
# ===================

@test "reset_retry_count clears the count" {
    local issue_number=99997
    
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "2" ]
    
    reset_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "0" ]
}

@test "reset_retry_count removes state file" {
    local issue_number=99996
    
    increment_retry_count "$issue_number"
    
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    [ -f "$state_file" ]
    
    reset_retry_count "$issue_number"
    
    [ ! -f "$state_file" ]
}

@test "reset_retry_count is idempotent" {
    local issue_number=99995
    
    # リセット前にカウントがなくてもエラーにならない
    reset_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "0" ]
}

# ===================
# should_continue_retry テスト
# ===================

@test "should_continue_retry returns true under max retries" {
    local issue_number=99994
    
    # 0回目は続行可能
    run should_continue_retry "$issue_number"
    [ "$status" -eq 0 ]
}

@test "should_continue_retry returns true at 1 retry" {
    local issue_number=99993
    
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 0 ]
}

@test "should_continue_retry returns true at 2 retries" {
    local issue_number=99992
    
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 0 ]
}

@test "should_continue_retry returns false at max retries" {
    # テスト用の独立した状態ディレクトリを設定
    export PI_RUNNER_STATE_DIR="$BATS_TEST_TMPDIR/state_max"
    mkdir -p "$PI_RUNNER_STATE_DIR"
    
    local issue_number="test_max_$$"
    
    # 3回インクリメントして最大に到達
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 1 ]
}

@test "should_continue_retry returns false over max retries" {
    # テスト用の独立した状態ディレクトリを設定
    export PI_RUNNER_STATE_DIR="$BATS_TEST_TMPDIR/state_over"
    mkdir -p "$PI_RUNNER_STATE_DIR"
    
    local issue_number="test_over_$$"
    
    # 4回インクリメント
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 1 ]
}

@test "should_continue_retry boundary test: MAX_RETRY_COUNT-1 is allowed" {
    local issue_number=99989
    
    # MAX_RETRY_COUNT-1回まで許可
    for ((i=0; i<MAX_RETRY_COUNT-1; i++)); do
        increment_retry_count "$issue_number"
    done
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 0 ]
}

@test "should_continue_retry boundary test: MAX_RETRY_COUNT is not allowed" {
    local issue_number=99988
    
    # MAX_RETRY_COUNT回で拒否
    for ((i=0; i<MAX_RETRY_COUNT; i++)); do
        increment_retry_count "$issue_number"
    done
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 1 ]
}
