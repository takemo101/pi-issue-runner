#!/usr/bin/env bash
# github.sh のテスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# モックライブラリを最初に読み込み
source "$SCRIPT_DIR/helpers/mocks.sh"

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
    
    # ghモックを自動設定（認証なし環境ではモックを使用）
    auto_mock_gh
    if is_gh_mocked; then
        echo "ℹ Using mocked gh for check_dependencies test"
    fi
    
    # 依存関係チェック
    if command -v jq &> /dev/null; then
        assert_success "check_dependencies succeeds with mock or authenticated gh" check_dependencies
    else
        echo "⊘ Skipping check_dependencies test (jq not installed)"
    fi
    
    # モックをクリーンアップ
    unmock_gh_function 2>/dev/null || true
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
# sanitize_issue_body テスト
# ===================
echo ""
echo "=== sanitize_issue_body tests ==="

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

assert_not_contains() {
    local description="$1"
    local pattern="$2"
    local actual="$3"
    if [[ "$actual" != *"$pattern"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (should not contain '$pattern')"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_contains_escaped() {
    local description="$1"
    local escaped="$2"
    local actual="$3"
    if [[ "$actual" == *"$escaped"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (should contain escaped pattern '$escaped')"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

# sanitize_issue_body関数が存在するかテスト
if declare -f sanitize_issue_body > /dev/null 2>&1; then
    echo "✓ sanitize_issue_body function exists"
    ((TESTS_PASSED++)) || true
    
    # 通常テキストは変更されない
    result=$(sanitize_issue_body "Normal text without any special patterns")
    assert_equals "sanitize_issue_body preserves normal text" \
        "Normal text without any special patterns" "$result"
    
    # 空文字列
    result=$(sanitize_issue_body "")
    assert_equals "sanitize_issue_body handles empty string" "" "$result"
    
    # コマンド置換 $(...) のエスケープ
    result=$(sanitize_issue_body 'Test $(whoami) command')
    assert_contains_escaped "sanitize_issue_body escapes command substitution" '\$(' "$result"
    
    # バッククォートのエスケープ
    result=$(sanitize_issue_body 'Test `ls -la` command')
    assert_contains_escaped "sanitize_issue_body escapes backticks" '\`' "$result"
    
    # 変数展開 ${...} のエスケープ
    result=$(sanitize_issue_body 'Test ${HOME} variable')
    assert_contains_escaped "sanitize_issue_body escapes variable expansion" '\${' "$result"
    
    # 複合パターン
    result=$(sanitize_issue_body 'Mixed $(cmd) and `cmd2` and ${VAR}')
    assert_contains_escaped "sanitize_issue_body escapes all patterns (cmd subst)" '\$(' "$result"
    assert_contains_escaped "sanitize_issue_body escapes all patterns (backtick)" '\`' "$result"
    assert_contains_escaped "sanitize_issue_body escapes all patterns (var expand)" '\${' "$result"
else
    echo "✗ sanitize_issue_body function does not exist"
    ((TESTS_FAILED++)) || true
fi

# ===================
# detect_dangerous_patterns テスト
# ===================
echo ""
echo "=== detect_dangerous_patterns tests ==="

if declare -f detect_dangerous_patterns > /dev/null 2>&1; then
    echo "✓ detect_dangerous_patterns function exists"
    ((TESTS_PASSED++)) || true
    
    # 安全なテキスト
    if detect_dangerous_patterns "Safe text" 2>/dev/null; then
        echo "✓ detect_dangerous_patterns returns success for safe text"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ detect_dangerous_patterns should return success for safe text"
        ((TESTS_FAILED++)) || true
    fi
    
    # 危険なパターン（コマンド置換）
    if ! detect_dangerous_patterns 'Dangerous $(rm -rf /)' 2>/dev/null; then
        echo "✓ detect_dangerous_patterns detects command substitution"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ detect_dangerous_patterns should detect command substitution"
        ((TESTS_FAILED++)) || true
    fi
    
    # 危険なパターン（バッククォート）
    if ! detect_dangerous_patterns 'Dangerous `rm -rf /`' 2>/dev/null; then
        echo "✓ detect_dangerous_patterns detects backticks"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ detect_dangerous_patterns should detect backticks"
        ((TESTS_FAILED++)) || true
    fi
    
    # 危険なパターン（変数展開）
    if ! detect_dangerous_patterns 'Dangerous ${PATH}' 2>/dev/null; then
        echo "✓ detect_dangerous_patterns detects variable expansion"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ detect_dangerous_patterns should detect variable expansion"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "✗ detect_dangerous_patterns function does not exist"
    ((TESTS_FAILED++)) || true
fi

# ===================
# ghモック関数テスト
# ===================
echo ""
echo "=== gh mock function tests ==="

# mock_gh_function が存在するかテスト
if declare -f mock_gh_function > /dev/null 2>&1; then
    echo "✓ mock_gh_function exists"
    ((TESTS_PASSED++)) || true
else
    echo "✗ mock_gh_function does not exist"
    ((TESTS_FAILED++)) || true
fi

# モックが正しく動作するかテスト
mock_gh_function

# is_gh_mocked のテスト
if is_gh_mocked; then
    echo "✓ is_gh_mocked returns true when mock is active"
    ((TESTS_PASSED++)) || true
else
    echo "✗ is_gh_mocked should return true when mock is active"
    ((TESTS_FAILED++)) || true
fi

# gh auth status のモック
if gh auth status 2>&1 | grep -q "mock-user"; then
    echo "✓ mocked gh auth status works"
    ((TESTS_PASSED++)) || true
else
    echo "✗ mocked gh auth status should return mock-user"
    ((TESTS_FAILED++)) || true
fi

# gh issue view のモック
mock_issue_result=$(gh issue view 99 --json number,title 2>&1)
if echo "$mock_issue_result" | grep -q '"number":99'; then
    echo "✓ mocked gh issue view returns correct issue number"
    ((TESTS_PASSED++)) || true
else
    echo "✗ mocked gh issue view should return issue 99"
    echo "  Got: $mock_issue_result"
    ((TESTS_FAILED++)) || true
fi

# unmock のテスト
unmock_gh_function

if ! is_gh_mocked; then
    echo "✓ is_gh_mocked returns false after unmock"
    ((TESTS_PASSED++)) || true
else
    echo "✗ is_gh_mocked should return false after unmock"
    ((TESTS_FAILED++)) || true
fi

# auto_mock_gh のテスト (USE_MOCK_GH=true)
USE_MOCK_GH=true auto_mock_gh
if is_gh_mocked; then
    echo "✓ auto_mock_gh with USE_MOCK_GH=true enables mock"
    ((TESTS_PASSED++)) || true
else
    echo "✗ auto_mock_gh with USE_MOCK_GH=true should enable mock"
    ((TESTS_FAILED++)) || true
fi
unmock_gh_function

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
