#!/usr/bin/env bash
# github.sh のテスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/github.sh"

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

# テストヘルパー
assert_success() {
    local description="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        ((TESTS_FAILED++)) || true
    fi
}

assert_failure() {
    local description="$1"
    shift
    if ! "$@" > /dev/null 2>&1; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        ((TESTS_FAILED++)) || true
    fi
}

assert_contains() {
    local description="$1"
    local expected="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if [[ "$output" == *"$expected"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (expected '$expected' in output)"
        echo "  Got: $output"
        ((TESTS_FAILED++)) || true
    fi
}

# ===================
# check_jq テスト
# ===================
echo "=== check_jq tests ==="

# check_jq関数が存在するかテスト
if declare -f check_jq > /dev/null 2>&1; then
    echo "✓ check_jq function exists"
    ((TESTS_PASSED++)) || true
    
    # jqが存在する場合のテスト
    if command -v jq &> /dev/null; then
        assert_success "check_jq succeeds when jq is installed" check_jq
    fi
else
    echo "✗ check_jq function does not exist"
    ((TESTS_FAILED++)) || true
fi

# ===================
# check_dependencies テスト
# ===================
echo ""
echo "=== check_dependencies tests ==="

# check_dependencies関数が存在するかテスト
if declare -f check_dependencies > /dev/null 2>&1; then
    echo "✓ check_dependencies function exists"
    ((TESTS_PASSED++)) || true
    
    # 依存関係チェック（gh auth statusはスキップ可能）
    if command -v jq &> /dev/null && command -v gh &> /dev/null && gh auth status &> /dev/null; then
        assert_success "check_dependencies succeeds when all deps installed and authenticated" check_dependencies
    else
        echo "⊘ Skipping check_dependencies test (gh not authenticated)"
    fi
else
    echo "✗ check_dependencies function does not exist"
    ((TESTS_FAILED++)) || true
fi

# ===================
# check_gh_cli テスト
# ===================
echo ""
echo "=== check_gh_cli tests ==="

if declare -f check_gh_cli > /dev/null 2>&1; then
    echo "✓ check_gh_cli function exists"
    ((TESTS_PASSED++)) || true
else
    echo "✗ check_gh_cli function does not exist"
    ((TESTS_FAILED++)) || true
fi

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
