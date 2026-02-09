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

@test "classify_ci_failure detects npm ERR as lint fallback" {
    # npm ERR! はテスト・ビルド両方で出るため、具体的パターンに
    # マッチしない場合はフォールバックで lint に分類される
    local log="npm ERR! code ELIFECYCLE"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure detects npm ERR with build error as build" {
    # npm ERR! + SyntaxError がある場合はビルドエラーに分類される
    local log="SyntaxError: Unexpected token
npm ERR! code ELIFECYCLE"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure detects npm ERR with test failure as test" {
    # npm ERR! + テスト失敗パターンがある場合はテスト失敗に分類される
    local log="Tests: 2 failed, 5 passed
npm ERR! code ELIFECYCLE"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
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

@test "get_failed_ci_logs uses --branch filter from PR head branch" {
    # gh をモックして、PR のヘッドブランチ取得と run list の呼び出しを検証
    gh() {
        case "$1" in
            pr)
                if [[ "$2" == "view" && "$4" == "--json" ]]; then
                    echo "feature/my-branch"
                    return 0
                fi
                ;;
            run)
                if [[ "$2" == "list" ]]; then
                    # --branch オプションが渡されていることを検証
                    local has_branch=false
                    for arg in "$@"; do
                        if [[ "$arg" == "--branch" ]]; then
                            has_branch=true
                        fi
                    done
                    if [[ "$has_branch" == "true" ]]; then
                        echo '12345'
                        return 0
                    else
                        echo "ERROR: --branch not passed" >&2
                        return 1
                    fi
                elif [[ "$2" == "view" ]]; then
                    echo "mock log output"
                    return 0
                fi
                ;;
        esac
    }
    export -f gh
    
    run get_failed_ci_logs 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock log output"* ]]
}

# ===================
# 誤分類防止テスト（Issue #1246）
# ===================

@test "classify_ci_failure does not misclassify Python DeprecationWarning as lint" {
    # Python の DeprecationWarning は lint ではない
    local log="DeprecationWarning: pkg_resources is deprecated
  import pkg_resources"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "classify_ci_failure does not misclassify Node ExperimentalWarning as lint" {
    # Node.js の ExperimentalWarning は lint ではない
    local log="(node:12345) ExperimentalWarning: The Fetch API is an experimental feature."
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "classify_ci_failure does not misclassify build FAILED as test" {
    # ビルドエラーに FAILED が含まれる場合、テストに誤分類しない
    local log="error[E0433]: failed to resolve: could not find module
cargo build FAILED"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure classifies compilation failed as build" {
    local log="compilation failed: exit status 2"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure detects ShellCheck errors as lint" {
    local log="In scripts/run.sh line 42:
  echo \$var
       ^---^ SC2086: Double quote to prevent globbing"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure detects pylint errors as lint" {
    local log="************* Module mypackage.main
mypackage/main.py:10:0: C0114: Missing module docstring (missing-module-docstring)
pylint returned exit code 4"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure detects flake8 errors as lint" {
    local log="src/main.py:1:1: flake8: E302 expected 2 blank lines, got 1"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure classifies Rust unused warning via fallback as lint" {
    # warning:.*unused は汎用フォールバックで lint に分類
    local log="warning: unused variable: \`x\`
  --> src/main.rs:5:9"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "lint" ]
}

@test "classify_ci_failure build takes priority over test when both present" {
    # ビルドエラーとテストパターンが両方あっても、ビルドが先にマッチ
    local log="error[E0425]: cannot find function 'foo'
test result: FAILED. 0 passed; 1 failed;"
    
    run classify_ci_failure "$log"
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure handles input starting with -n" {
    run classify_ci_failure '-n Diff in foo.rs'
    [ "$status" -eq 0 ]
    [ "$output" = "format" ]
}

@test "classify_ci_failure handles input starting with -e" {
    run classify_ci_failure '-e error[E0425]: cannot find value'
    [ "$status" -eq 0 ]
    [ "$output" = "build" ]
}

@test "classify_ci_failure handles input starting with -E" {
    run classify_ci_failure '-E test result: FAILED. 0 passed; 1 failed;'
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

# ===================
# get_failed_ci_logs テスト
# ===================

@test "get_failed_ci_logs falls back when PR head branch unavailable" {
    # gh pr view が失敗する場合のフォールバック
    gh() {
        case "$1" in
            pr)
                return 1  # PR情報取得失敗
                ;;
            run)
                if [[ "$2" == "list" ]]; then
                    echo '67890'
                    return 0
                elif [[ "$2" == "view" ]]; then
                    echo "fallback log output"
                    return 0
                fi
                ;;
        esac
    }
    export -f gh
    
    run get_failed_ci_logs 999
    [ "$status" -eq 0 ]
    [[ "$output" == *"fallback log output"* ]]
}
