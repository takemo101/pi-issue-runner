#!/usr/bin/env bats
# ci-fix.bats - CI自動修正機能のテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 状態ファイルのクリーンアップ
    rm -f /tmp/pi-runner-ci-retry-*
    
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/ci-fix.sh"
}

teardown() {
    # リトライ状態ファイルのクリーンアップ
    rm -f /tmp/pi-runner-ci-retry-*
    
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# classify_ci_failure テスト
# ===================

@test "classify_ci_failure detects format errors" {
    local log="Diff in src/main.rs at line 10:
-    let x=1;
+    let x = 1;"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "format" ]
}

@test "classify_ci_failure detects format errors with 'would have been reformatted'" {
    local log="error: the file src/main.rs would have been reformatted"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "format" ]
}

@test "classify_ci_failure detects lint/clippy errors" {
    local log="warning: unused import: 'std::io'
  --> src/main.rs:3:5
   |
3 | use std::io;
   |     ^^^^^^^"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure detects clippy warnings" {
    local log="error: clippy::unused_variables"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure detects test failures" {
    local log="test test_add ... FAILED
failures:
---- test_add stdout ----"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

@test "classify_ci_failure detects test result failures" {
    local log="test result: FAILED. 2 passed; 1 failed;"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

@test "classify_ci_failure detects build errors" {
    local log="error[E0425]: cannot find function 'foo' in this scope"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure detects unresolved import errors" {
    local log="error: unresolved import 'crate::module'"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure returns unknown for unrecognized errors" {
    local log="Some random error message that doesn't match any pattern"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

# ===================
# リトライ管理テスト
# ===================

@test "get_retry_count returns 0 for new issue" {
    run get_retry_count 99999
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

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

@test "reset_retry_count clears the count" {
    local issue_number=99998
    
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "2" ]
    
    reset_retry_count "$issue_number"
    
    run get_retry_count "$issue_number"
    [ "$output" = "0" ]
}

@test "should_continue_retry returns true under max retries" {
    local issue_number=99997
    
    # 0回目は続行可能
    run should_continue_retry "$issue_number"
    [ "$status" -eq 0 ]
    
    # 2回まで続行可能
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 0 ]
}

@test "should_continue_retry returns false at max retries" {
    local issue_number=99996
    
    # 3回インクリメントして最大に到達
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 1 ]
}

@test "should_continue_retry returns false over max retries" {
    local issue_number=99995
    
    # 4回インクリメント
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    increment_retry_count "$issue_number"
    
    run should_continue_retry "$issue_number"
    [ "$status" -eq 1 ]
}

# ===================
# try_auto_fix テスト（モック使用）
# ===================

@test "try_auto_fix returns 2 for test failures (requires AI)" {
    # cargoがない環境でもテストできるようにスキップ
    if ! command -v cargo &> /dev/null; then
        skip "cargo not available"
    fi
    
    cd "$BATS_TEST_TMPDIR"
    
    run try_auto_fix "test" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix returns 2 for build errors (requires AI)" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_auto_fix "build" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix returns 2 for unknown failure type" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_auto_fix "unknown" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

# ===================
# 定数テスト
# ===================

@test "constants are defined correctly" {
    [[ "$CI_POLL_INTERVAL" == "30" ]]
    [[ "$CI_TIMEOUT" == "600" ]]
    [[ "$MAX_RETRY_COUNT" == "3" ]]
    [[ "$FAILURE_TYPE_LINT" == "lint" ]]
    [[ "$FAILURE_TYPE_FORMAT" == "format" ]]
    [[ "$FAILURE_TYPE_TEST" == "test" ]]
    [[ "$FAILURE_TYPE_BUILD" == "build" ]]
    [[ "$FAILURE_TYPE_UNKNOWN" == "unknown" ]]
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
