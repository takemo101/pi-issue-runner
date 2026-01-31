#!/usr/bin/env bash
# Issue #21, #22, #23 の修正テスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/tmux.sh"

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

# ===================
# Issue #23: 設定ファイル名テスト
# ===================
echo "=== Issue #23: Config file name tests ==="

config_source=$(cat "$PROJECT_ROOT/lib/config.sh")
assert_contains "config uses .pi-runner.yaml" '.pi-runner.yaml' "$config_source"

# ===================
# Issue #22: セッション名テスト
# ===================
echo ""
echo "=== Issue #22: Session name tests ==="

# デフォルトprefix "pi-issue" の場合
CONFIG_TMUX_SESSION_PREFIX="pi-issue"
result="$(generate_session_name 42)"
assert_equals "generate_session_name with pi-issue prefix" "pi-issue-42" "$result"

# カスタムprefix "dev" の場合
CONFIG_TMUX_SESSION_PREFIX="dev"
result="$(generate_session_name 42)"
assert_equals "generate_session_name with dev prefix" "dev-issue-42" "$result"

# extract_issue_number テスト
assert_equals "extract from pi-issue-42" "42" "$(extract_issue_number "pi-issue-42")"
assert_equals "extract from dev-issue-99" "99" "$(extract_issue_number "dev-issue-99")"
assert_equals "extract from pi-issue-42-feature" "42" "$(extract_issue_number "pi-issue-42-feature")"
assert_equals "extract from custom-issue-123-bugfix" "123" "$(extract_issue_number "custom-issue-123-bugfix")"

# 往復テスト
CONFIG_TMUX_SESSION_PREFIX="pi-issue"
for num in 1 42 99 123; do
    session="$(generate_session_name "$num")"
    extracted="$(extract_issue_number "$session")"
    assert_equals "round-trip for issue $num" "$num" "$extracted"
done

# ===================
# Issue #21: プロンプト構築テスト
# ===================
echo ""
echo "=== Issue #21: Prompt construction tests ==="

run_source=$(cat "$PROJECT_ROOT/scripts/run.sh")

assert_contains "run.sh gets issue body" 'get_issue_body' "$run_source"
assert_contains "run.sh creates prompt file" '.pi-prompt.md' "$run_source"
assert_contains "run.sh includes issue title in prompt" 'issue_title' "$run_source"
assert_contains "run.sh includes issue body in prompt" 'issue_body' "$run_source"
# @でファイル参照する方式をテスト
if grep -q '@.*prompt_file' "$PROJECT_ROOT/scripts/run.sh"; then
    echo "✓ run.sh uses @ to reference prompt file"
    ((TESTS_PASSED++)) || true
else
    echo "✗ run.sh uses @ to reference prompt file"
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
