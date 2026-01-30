#!/usr/bin/env bash
# cleanup.sh のテスト

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

# ===================
# Usage テスト
# ===================
echo "=== cleanup.sh usage tests ==="

usage_output=$("$SCRIPT_DIR/../scripts/cleanup.sh" --help 2>&1) || true

assert_contains "--delete-branch option in usage" "--delete-branch" "$usage_output"
assert_contains "delete branch description" "Gitブランチも削除" "$usage_output"
assert_contains "example with --delete-branch" "--delete-branch" "$usage_output"

# ===================
# オプションパース テスト
# ===================
echo ""
echo "=== Option parsing tests ==="

# cleanup.shのソースを確認
cleanup_source=$(cat "$SCRIPT_DIR/../scripts/cleanup.sh")

assert_contains "delete_branch variable exists" 'delete_branch=' "$cleanup_source"
assert_contains "--delete-branch case exists" '--delete-branch)' "$cleanup_source"
assert_contains "branch deletion logic exists" 'git branch -d' "$cleanup_source"
assert_contains "force branch deletion logic exists" 'git branch -D' "$cleanup_source"
assert_contains "get_worktree_branch call exists" 'get_worktree_branch' "$cleanup_source"

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
