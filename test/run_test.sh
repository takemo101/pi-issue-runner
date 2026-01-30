#!/usr/bin/env bash
# run.sh のテスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
        echo "  Expected to contain: '$expected'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

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
# Usage テスト
# ===================
echo "=== run.sh usage tests ==="

usage_output=$("$PROJECT_ROOT/scripts/run.sh" --help 2>&1) || true

assert_contains "--reattach option in usage" "--reattach" "$usage_output"
assert_contains "--force option in usage" "--force" "$usage_output"
assert_contains "reattach description" "既存セッション" "$usage_output"
assert_contains "force description" "削除して再作成" "$usage_output"
assert_contains "reattach example" "--reattach" "$usage_output"
assert_contains "force example" "--force" "$usage_output"

# ===================
# オプションパース テスト
# ===================
echo ""
echo "=== Option parsing tests ==="

run_source=$(cat "$PROJECT_ROOT/scripts/run.sh")

assert_contains "reattach variable exists" 'reattach=' "$run_source"
assert_contains "--reattach case exists" '--reattach)' "$run_source"
assert_contains "force variable exists" 'force=' "$run_source"
assert_contains "--force case exists" '--force)' "$run_source"

# ===================
# 既存セッション検出ロジック テスト
# ===================
echo ""
echo "=== Existing session detection tests ==="

assert_contains "session_exists check" 'session_exists "$session_name"' "$run_source"
assert_contains "reattach logic" 'if [[ "$reattach" == "true" ]]' "$run_source"
assert_contains "force session removal" 'kill_session "$session_name"' "$run_source"
assert_contains "error message for existing session" "already exists" "$run_source"

# ===================
# 既存Worktree検出ロジック テスト
# ===================
echo ""
echo "=== Existing worktree detection tests ==="

assert_contains "find_worktree_by_issue check" 'find_worktree_by_issue' "$run_source"
assert_contains "force worktree removal" 'remove_worktree' "$run_source"

# ===================
# エラー時のヘルプ表示テスト
# ===================
echo ""
echo "=== Error help tests ==="

error_output=$("$PROJECT_ROOT/scripts/run.sh" 2>&1) || true

assert_contains "error shows usage hint" "required" "$error_output"

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
