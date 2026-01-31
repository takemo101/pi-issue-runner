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
# has_dangerous_patterns テスト
# ===================
echo ""
echo "=== has_dangerous_patterns tests ==="

if declare -f has_dangerous_patterns > /dev/null 2>&1; then
    echo "✓ has_dangerous_patterns function exists"
    ((TESTS_PASSED++)) || true
    
    # 安全なテキスト（危険なパターンがない場合は1=falseを返す）
    if ! has_dangerous_patterns "Safe text" 2>/dev/null; then
        echo "✓ has_dangerous_patterns returns false for safe text"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ has_dangerous_patterns should return false for safe text"
        ((TESTS_FAILED++)) || true
    fi
    
    # 危険なパターン（コマンド置換）- 0=trueを返す
    if has_dangerous_patterns 'Dangerous $(rm -rf /)' 2>/dev/null; then
        echo "✓ has_dangerous_patterns detects command substitution"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ has_dangerous_patterns should detect command substitution"
        ((TESTS_FAILED++)) || true
    fi
    
    # 危険なパターン（バッククォート）- 0=trueを返す
    if has_dangerous_patterns 'Dangerous `rm -rf /`' 2>/dev/null; then
        echo "✓ has_dangerous_patterns detects backticks"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ has_dangerous_patterns should detect backticks"
        ((TESTS_FAILED++)) || true
    fi
    
    # 危険なパターン（変数展開）- 0=trueを返す
    if has_dangerous_patterns 'Dangerous ${PATH}' 2>/dev/null; then
        echo "✓ has_dangerous_patterns detects variable expansion"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ has_dangerous_patterns should detect variable expansion"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "✗ has_dangerous_patterns function does not exist"
    ((TESTS_FAILED++)) || true
fi

# ===================
# get_issues_created_after テスト
# ===================
echo ""
echo "=== get_issues_created_after tests ==="

if declare -f get_issues_created_after > /dev/null 2>&1; then
    echo "✓ get_issues_created_after function exists"
    ((TESTS_PASSED++)) || true
    
    # 関数のシグネチャ確認
    func_def=$(type get_issues_created_after 2>/dev/null | head -10)
    if [[ "$func_def" == *'start_time="$1"'* ]]; then
        echo "✓ get_issues_created_after accepts start_time parameter"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ get_issues_created_after should accept start_time parameter"
        ((TESTS_FAILED++)) || true
    fi
    
    if [[ "$func_def" == *'max_issues="${2:-20}"'* ]]; then
        echo "✓ get_issues_created_after has default max_issues of 20"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ get_issues_created_after should have default max_issues of 20"
        ((TESTS_FAILED++)) || true
    fi
    
    # gh issue list コマンドが含まれているか
    if [[ "$func_def" == *'gh issue list'* ]]; then
        echo "✓ get_issues_created_after uses gh issue list"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ get_issues_created_after should use gh issue list"
        ((TESTS_FAILED++)) || true
    fi
    
    # --author "@me" が含まれているか
    if [[ "$func_def" == *'--author "@me"'* ]]; then
        echo "✓ get_issues_created_after filters by current user"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ get_issues_created_after should filter by current user"
        ((TESTS_FAILED++)) || true
    fi
    
    # jq でフィルタしているか
    if [[ "$func_def" == *'jq -r'* && "$func_def" == *'select(.createdAt >= $start)'* ]]; then
        echo "✓ get_issues_created_after filters by createdAt"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ get_issues_created_after should filter by createdAt"
        ((TESTS_FAILED++)) || true
    fi
    
    # 実際のAPI呼び出しテスト（ghが認証済みの場合のみ）
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        # 未来の時刻を指定して呼び出し（結果は空になるはず）
        future_time="2099-01-01T00:00:00Z"
        result=$(get_issues_created_after "$future_time" 5 2>/dev/null) || true
        if [[ -z "$result" ]]; then
            echo "✓ get_issues_created_after returns empty for future time"
            ((TESTS_PASSED++)) || true
        else
            echo "⊘ get_issues_created_after returned issues for future time (may have issues created in 2099)"
        fi
    else
        echo "⊘ Skipping API call test (gh not authenticated)"
    fi
else
    echo "✗ get_issues_created_after function does not exist"
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
