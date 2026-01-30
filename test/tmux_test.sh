#!/usr/bin/env bash
# tmux.sh のテスト（Issue番号抽出）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

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

# ===================
# extract_issue_number テスト
# ===================
echo "=== extract_issue_number tests ==="

# 基本パターン
assert_equals "pi-issue-42" "42" "$(extract_issue_number "pi-issue-42")"
assert_equals "pi-issue-123" "123" "$(extract_issue_number "pi-issue-123")"
assert_equals "pi-issue-1" "1" "$(extract_issue_number "pi-issue-1")"

# サフィックス付き（問題のケース）
assert_equals "pi-issue-42-feature" "42" "$(extract_issue_number "pi-issue-42-feature")"
assert_equals "pi-issue-42-bug-fix" "42" "$(extract_issue_number "pi-issue-42-bug-fix")"
assert_equals "pi-issue-99-test-branch-name" "99" "$(extract_issue_number "pi-issue-99-test-branch-name")"

# 異なるプレフィックス
assert_equals "custom-issue-55" "55" "$(extract_issue_number "custom-issue-55")"
assert_equals "dev-issue-100-feature" "100" "$(extract_issue_number "dev-issue-100-feature")"

# フォールバックケース
assert_equals "session-42" "42" "$(extract_issue_number "session-42")"
assert_equals "task-123-name" "123" "$(extract_issue_number "task-123-name")"

# ===================
# generate_session_name テスト
# ===================
echo ""
echo "=== generate_session_name tests ==="

# デフォルトプレフィックスの場合
_CONFIG_LOADED=""
CONFIG_TMUX_SESSION_PREFIX="pi"
result="$(generate_session_name 42)"
assert_equals "generate_session_name 42" "pi-issue-42" "$result"

result="$(generate_session_name 123)"
assert_equals "generate_session_name 123" "pi-issue-123" "$result"

# ===================
# 往復テスト（generate → extract）
# ===================
echo ""
echo "=== Round-trip tests ==="

for issue_num in 1 42 99 123 9999; do
    session="$(generate_session_name "$issue_num")"
    extracted="$(extract_issue_number "$session")"
    assert_equals "round-trip for issue $issue_num" "$issue_num" "$extracted"
done

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
