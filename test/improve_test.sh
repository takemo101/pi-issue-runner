#!/usr/bin/env bash
# improve.sh のテスト

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPROVE_SCRIPT="$SCRIPT_DIR/../scripts/improve.sh"

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_contains() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected to contain: '$expected'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_success() {
    local description="$1"
    local exit_code="$2"
    if [[ "$exit_code" -eq 0 ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (exit code: $exit_code)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_failure() {
    local description="$1"
    local exit_code="$2"
    if [[ "$exit_code" -ne 0 ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (expected failure but got success)"
        ((TESTS_FAILED++)) || true
    fi
}

# ===================
# ヘルプオプションのテスト
# ===================
echo "=== improve.sh help option tests ==="

# --help オプション
result=$("$IMPROVE_SCRIPT" --help 2>&1)
exit_code=$?
assert_success "--help returns success" "$exit_code"
assert_contains "--help shows usage" "Usage:" "$result"
assert_contains "--help shows --max-iterations option" "--max-iterations" "$result"
assert_contains "--help shows --max-issues option" "--max-issues" "$result"
assert_contains "--help shows --auto-continue option" "--auto-continue" "$result"
assert_contains "--help shows --dry-run option" "--dry-run" "$result"
assert_contains "--help shows --timeout option" "--timeout" "$result"
assert_contains "--help shows --review-only option" "--review-only" "$result"
assert_contains "--help shows -v/--verbose option" "--verbose" "$result"
assert_contains "--help shows -h/--help option" "--help" "$result"
assert_contains "--help shows description" "Description:" "$result"
assert_contains "--help shows examples" "Examples:" "$result"
assert_contains "--help shows environment variables" "Environment Variables:" "$result"

# -h オプション
result=$("$IMPROVE_SCRIPT" -h 2>&1)
exit_code=$?
assert_success "-h returns success" "$exit_code"
assert_contains "-h shows usage" "Usage:" "$result"

# ===================
# オプションパースのテスト
# ===================
echo ""
echo "=== improve.sh option parsing tests ==="

# 不明なオプション
result=$("$IMPROVE_SCRIPT" --unknown-option 2>&1)
exit_code=$?
assert_failure "improve.sh with unknown option fails" "$exit_code"
assert_contains "error message mentions unknown option" "Unknown option" "$result"

# 不要な位置引数
result=$("$IMPROVE_SCRIPT" unexpected-arg 2>&1)
exit_code=$?
assert_failure "improve.sh with unexpected argument fails" "$exit_code"
assert_contains "error message mentions unexpected argument" "Unexpected argument" "$result"

# ===================
# スクリプトソースコードの構造テスト
# ===================
echo ""
echo "=== Script structure tests ==="

# スクリプトの構文チェック
bash -n "$IMPROVE_SCRIPT" 2>&1
exit_code=$?
assert_success "improve.sh has valid bash syntax" "$exit_code"

# ソースコードの内容確認
improve_source=$(cat "$IMPROVE_SCRIPT")

assert_contains "script sources config.sh" "lib/config.sh" "$improve_source"
assert_contains "script sources log.sh" "lib/log.sh" "$improve_source"
assert_contains "script sources status.sh" "lib/status.sh" "$improve_source"
assert_contains "script has main function" "main()" "$improve_source"
assert_contains "script has usage function" "usage()" "$improve_source"
assert_contains "script has check_dependencies function" "check_dependencies()" "$improve_source"
assert_contains "script has review_and_create_issues function" "review_and_create_issues()" "$improve_source"

# ===================
# オプション処理のテスト
# ===================
echo ""
echo "=== Option handling tests ==="

# --max-iterations
assert_contains "script handles --max-iterations" '--max-iterations)' "$improve_source"
assert_contains "script has max_iterations variable" 'max_iterations=' "$improve_source"

# --max-issues
assert_contains "script handles --max-issues" '--max-issues)' "$improve_source"
assert_contains "script has max_issues variable" 'max_issues=' "$improve_source"

# --auto-continue
assert_contains "script handles --auto-continue" '--auto-continue)' "$improve_source"
assert_contains "script has auto_continue variable" 'auto_continue=' "$improve_source"

# --dry-run
assert_contains "script handles --dry-run" '--dry-run)' "$improve_source"
assert_contains "script has dry_run variable" 'dry_run=' "$improve_source"

# --review-only
assert_contains "script handles --review-only" '--review-only)' "$improve_source"
assert_contains "script has review_only variable" 'review_only=' "$improve_source"

# --timeout
assert_contains "script handles --timeout" '--timeout)' "$improve_source"
assert_contains "script has timeout variable" 'timeout=' "$improve_source"

# -v/--verbose
assert_contains "script handles -v option" '-v|--verbose)' "$improve_source"
assert_contains "script sets LOG_LEVEL to DEBUG" 'LOG_LEVEL="DEBUG"' "$improve_source"

# ===================
# デフォルト値のテスト
# ===================
echo ""
echo "=== Default values tests ==="

assert_contains "max_iterations default is 3" 'max_iterations=3' "$improve_source"
assert_contains "max_issues default is 5" 'max_issues=5' "$improve_source"
assert_contains "auto_continue default is false" 'auto_continue=false' "$improve_source"
assert_contains "dry_run default is false" 'dry_run=false' "$improve_source"
assert_contains "review_only default is false" 'review_only=false' "$improve_source"
assert_contains "timeout default is 3600" 'timeout=3600' "$improve_source"

# ===================
# 依存関係チェックのテスト
# ===================
echo ""
echo "=== Dependency check tests ==="

# check_dependencies関数の内容確認
assert_contains "checks for pi command" 'pi_command' "$improve_source"
assert_contains "checks for gh command" 'command -v gh' "$improve_source"
assert_contains "checks for tmux command" 'command -v tmux' "$improve_source"
assert_contains "reports missing dependencies" 'Missing dependencies' "$improve_source"

# ===================
# レビューとIssue作成のテスト
# ===================
echo ""
echo "=== Review and create issues tests ==="

assert_contains "uses project-review skill" 'project-review' "$improve_source"
assert_contains "has CREATED_ISSUES marker" '###CREATED_ISSUES###' "$improve_source"
assert_contains "has END_ISSUES marker" '###END_ISSUES###' "$improve_source"
assert_contains "extracts issue numbers" 'CREATED_ISSUES+=(' "$improve_source"

# ===================
# ワークフローのテスト
# ===================
echo ""
echo "=== Workflow tests ==="

# イテレーションループ
assert_contains "has iteration loop" 'while [[ $iteration -le $max_iterations ]]' "$improve_source"

# フェーズ確認
assert_contains "has review phase" '[REVIEW]' "$improve_source"
assert_contains "has run phase" '[RUN]' "$improve_source"
assert_contains "has wait phase" '[WAIT]' "$improve_source"

# 承認ゲート
assert_contains "has approval gate" 'read -r -p' "$improve_source"
assert_contains "allows skip with auto-continue" 'auto_continue" != "true"' "$improve_source"

# 完了メッセージ
assert_contains "shows completion message" '改善完了' "$improve_source"
assert_contains "shows max iterations message" '最大イテレーション数' "$improve_source"

# ===================
# dry-runモードのテスト
# ===================
echo ""
echo "=== Dry-run mode tests ==="

assert_contains "dry-run skips execution" '--dry-run モードのため、実行をスキップ' "$improve_source"
assert_contains "dry-run shows would-create marker" '###WOULD_CREATE_ISSUES###' "$improve_source"

# ===================
# 結果サマリー
# ===================
echo ""
echo "===================="
echo "Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "===================="

exit $TESTS_FAILED
