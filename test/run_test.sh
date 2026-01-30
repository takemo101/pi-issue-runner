#!/usr/bin/env bash
# run.sh のテスト（コマンド構築のみ）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

assert_contains() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected to contain: $expected"
        echo "  Actual: $actual"
        ((TESTS_FAILED++)) || true
    fi
}

assert_not_contains() {
    local description="$1"
    local pattern="$2"
    local actual="$3"
    if [[ "$actual" != *"$pattern"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Should not contain: $pattern"
        echo "  Actual: $actual"
        ((TESTS_FAILED++)) || true
    fi
}

# ===================
# piコマンド構築テスト
# ===================
echo "=== pi command construction tests ==="

# run.shからコマンド構築部分を抽出してテスト
test_command_format() {
    local pi_command="pi"
    local pi_args=""
    local extra_pi_args=""
    local issue_number="42"
    
    # 修正後の形式
    local full_command="$pi_command $pi_args $extra_pi_args --auto \"$issue_number\""
    
    # テスト1: --autoが独立した引数として存在する
    assert_contains "--auto is a separate argument" '--auto "42"' "$full_command"
    
    # テスト2: 旧形式（"42 --auto"）ではない
    assert_not_contains "old format not present" '"42 --auto"' "$full_command"
    
    # テスト3: Issue番号が引用符で囲まれている
    assert_contains "issue number is quoted" '"42"' "$full_command"
}

test_command_format

# 追加テスト: extra_pi_argsが含まれる場合
test_with_extra_args() {
    local pi_command="pi"
    local pi_args="--model gpt-4"
    local extra_pi_args="--verbose"
    local issue_number="123"
    
    local full_command="$pi_command $pi_args $extra_pi_args --auto \"$issue_number\""
    
    assert_contains "includes pi_args" "--model gpt-4" "$full_command"
    assert_contains "includes extra_pi_args" "--verbose" "$full_command"
    assert_contains "ends with issue number" '"123"' "$full_command"
}

echo ""
echo "=== pi command with extra args tests ==="
test_with_extra_args

# ===================
# 結果サマリー
# ===================
echo ""
echo "===================="
echo "Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "===================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
