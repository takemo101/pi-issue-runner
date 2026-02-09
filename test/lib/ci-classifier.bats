#!/usr/bin/env bats
# ci-classifier.bats - CI失敗タイプ分類機能のテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/ci-classifier.sh"
}

teardown() {
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# 定数テスト
# ===================

@test "classifier constants are defined correctly" {
    [[ "$FAILURE_TYPE_LINT" == "lint" ]]
    [[ "$FAILURE_TYPE_FORMAT" == "format" ]]
    [[ "$FAILURE_TYPE_TEST" == "test" ]]
    [[ "$FAILURE_TYPE_BUILD" == "build" ]]
    [[ "$FAILURE_TYPE_UNKNOWN" == "unknown" ]]
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

@test "classify_ci_failure detects fmt check failures" {
    local log="fmt check failed"
    
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

@test "classify_ci_failure detects clippy compile errors" {
    local log="error: could not compile with clippy"
    
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

# ===================
# Bats テスト失敗パターン
# ===================

@test "classify_ci_failure detects Bats 'not ok' failures" {
    local log="not ok 5 get_config returns default value"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

@test "classify_ci_failure detects Bats summary failures" {
    local log="49 tests, 1 failure"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

@test "classify_ci_failure detects Bats plural failures" {
    local log="10 tests, 3 failures"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

# ===================
# Go テスト失敗パターン
# ===================

@test "classify_ci_failure detects Go FAIL prefix" {
    local log="--- FAIL: TestExample (0.00s)"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

@test "classify_ci_failure detects Go FAIL tab pattern" {
    local log=$'FAIL\texample.com/pkg\t0.005s'
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

# ===================
# Node/Jest テスト失敗パターン
# ===================

@test "classify_ci_failure detects Jest test failures" {
    local log="Tests: 3 failed, 10 passed"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

# ===================
# ESLint パターン
# ===================

@test "classify_ci_failure detects ESLint errors" {
    local log="✖ 5 problems (3 errors, 2 warnings)"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure detects ESLint single problem" {
    local log="✖ 1 problem (1 error, 0 warnings)"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

# ===================
# Node ビルドエラーパターン
# ===================

@test "classify_ci_failure detects npm ERR" {
    local log="npm ERR! code ELIFECYCLE"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure detects SyntaxError" {
    local log="SyntaxError: Unexpected token"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure detects ModuleNotFoundError" {
    local log="ModuleNotFoundError: No module named 'requests'"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

# ===================
# Go ビルドエラーパターン
# ===================

@test "classify_ci_failure detects Go build errors" {
    local log="go build: cannot load example.com/pkg"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

# ===================
# Bash フォーマットパターン
# ===================

@test "classify_ci_failure detects shfmt format errors" {
    local log="shfmt: scripts/run.sh: formatting differs"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "format" ]
}

# ===================
# unknown パターン
# ===================

@test "classify_ci_failure returns unknown for unrecognized errors" {
    local log="Some random error message that doesn't match any pattern"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "classify_ci_failure prioritizes format over other types" {
    # formatエラーとlintエラーが両方ある場合、formatが優先される
    local log="error: clippy::unused_variables
Diff in src/main.rs at line 10:
-    let x=1;
+    let x = 1;"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "format" ]
}

# ===================
# get_failed_ci_logs テスト
# ===================

@test "get_failed_ci_logs function exists" {
    declare -f get_failed_ci_logs
}

@test "get_failed_ci_logs returns error when gh CLI is not available" {
    (
        unset -f gh 2>/dev/null || true
        PATH="/bin:/usr/bin"
        run get_failed_ci_logs 123
        [ "$status" -eq 1 ]
    )
}
