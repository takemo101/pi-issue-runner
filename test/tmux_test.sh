#!/usr/bin/env bash
# tmux.sh のテスト

# テスト用にエラーで終了しないように
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# lib/tmux.shに必要な依存関係
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

# テスト用にエラーで終了しないように再設定（sourceで上書きされるため）
set +e

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

assert_not_empty() {
    local description="$1"
    local actual="$2"
    if [[ -n "$actual" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (value is empty)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_empty() {
    local description="$1"
    local actual="$2"
    if [[ -z "$actual" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (value is not empty: '$actual')"
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
# generate_session_name テスト
# ===================
echo "=== generate_session_name tests ==="

# デフォルト設定を使用
_CONFIG_LOADED=""
CONFIG_TMUX_SESSION_PREFIX="pi"
load_config

result=$(generate_session_name "42")
assert_equals "generate_session_name with number 42" "pi-issue-42" "$result"

result=$(generate_session_name "123")
assert_equals "generate_session_name with number 123" "pi-issue-123" "$result"

result=$(generate_session_name "1")
assert_equals "generate_session_name with single digit" "pi-issue-1" "$result"

# カスタムプレフィックス
_CONFIG_LOADED=""
export PI_RUNNER_TMUX_SESSION_PREFIX="myproject"
load_config

result=$(generate_session_name "99")
assert_equals "generate_session_name with custom prefix" "myproject-issue-99" "$result"

unset PI_RUNNER_TMUX_SESSION_PREFIX

# プレフィックスに既に-issueが含まれている場合
_CONFIG_LOADED=""
export PI_RUNNER_TMUX_SESSION_PREFIX="myproject-issue"
load_config

result=$(generate_session_name "99")
assert_equals "generate_session_name with -issue prefix (no duplicate)" "myproject-issue-99" "$result"

unset PI_RUNNER_TMUX_SESSION_PREFIX

# ===================
# extract_issue_number テスト
# ===================
echo ""
echo "=== extract_issue_number tests ==="

result=$(extract_issue_number "pi-issue-42")
assert_equals "extract from 'pi-issue-42'" "42" "$result"

result=$(extract_issue_number "pi-issue-123")
assert_equals "extract from 'pi-issue-123'" "123" "$result"

result=$(extract_issue_number "myproject-issue-99")
assert_equals "extract from 'myproject-issue-99'" "99" "$result"

result=$(extract_issue_number "pi-issue-42-feature")
assert_equals "extract from 'pi-issue-42-feature'" "42" "$result"

result=$(extract_issue_number "pi-issue-42-fix-bug")
assert_equals "extract from 'pi-issue-42-fix-bug'" "42" "$result"

# フォールバック: 末尾の数字
result=$(extract_issue_number "session-42")
assert_equals "extract from 'session-42' (fallback)" "42" "$result"

# 最初の数字列にフォールバック
result=$(extract_issue_number "feature123-test")
assert_equals "extract from 'feature123-test' (first number fallback)" "123" "$result"

# 数字がない場合
result=$(extract_issue_number "no-numbers-here" 2>/dev/null) || true
assert_empty "extract from 'no-numbers-here' returns empty" "$result"

# ===================
# session_exists テスト（モック不要、直接テスト）
# ===================
echo ""
echo "=== session_exists tests ==="

# 存在しないセッション
if session_exists "nonexistent-session-name-xyz123" 2>/dev/null; then
    exit_code=0
else
    exit_code=1
fi
assert_failure "session_exists returns failure for nonexistent session" "$exit_code"

# 注: 実際に存在するセッションのテストはtmux環境が必要なためスキップ

# ===================
# check_concurrent_limit テスト
# ===================
echo ""
echo "=== check_concurrent_limit tests ==="

# 無制限の場合（0）
_CONFIG_LOADED=""
export PI_RUNNER_PARALLEL_MAX_CONCURRENT="0"
load_config

check_concurrent_limit 2>/dev/null
exit_code=$?
assert_success "check_concurrent_limit with max=0 (unlimited)" "$exit_code"

unset PI_RUNNER_PARALLEL_MAX_CONCURRENT

# 無制限の場合（空）
_CONFIG_LOADED=""
export PI_RUNNER_PARALLEL_MAX_CONCURRENT=""
load_config

check_concurrent_limit 2>/dev/null
exit_code=$?
assert_success "check_concurrent_limit with max='' (unlimited)" "$exit_code"

unset PI_RUNNER_PARALLEL_MAX_CONCURRENT

# 高い制限値（通常は超えない）
_CONFIG_LOADED=""
export PI_RUNNER_PARALLEL_MAX_CONCURRENT="100"
load_config

check_concurrent_limit 2>/dev/null
exit_code=$?
assert_success "check_concurrent_limit with max=100 (high limit)" "$exit_code"

unset PI_RUNNER_PARALLEL_MAX_CONCURRENT

# ===================
# count_active_sessions テスト
# ===================
echo ""
echo "=== count_active_sessions tests ==="

# カウントが数値であることを確認
_CONFIG_LOADED=""
CONFIG_TMUX_SESSION_PREFIX="pi"
load_config

result=$(count_active_sessions 2>/dev/null)
if [[ "$result" =~ ^[0-9]+$ ]]; then
    echo "✓ count_active_sessions returns a number: $result"
    ((TESTS_PASSED++)) || true
else
    echo "✗ count_active_sessions should return a number, got: '$result'"
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
