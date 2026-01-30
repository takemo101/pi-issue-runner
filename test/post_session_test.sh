#!/usr/bin/env bash
# post-session.sh のテスト

# テスト用にエラーで終了しないように
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# lib に必要な依存関係
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"

# テスト用にエラーで終了しないように再設定
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
# post-session.sh 基本テスト
# ===================
echo "=== post-session.sh basic tests ==="

# スクリプトの存在確認
if [[ -f "$SCRIPT_DIR/../scripts/post-session.sh" ]]; then
    echo "✓ post-session.sh exists"
    ((TESTS_PASSED++)) || true
else
    echo "✗ post-session.sh not found"
    ((TESTS_FAILED++)) || true
fi

# 実行可能か確認
if [[ -x "$SCRIPT_DIR/../scripts/post-session.sh" ]]; then
    echo "✓ post-session.sh is executable"
    ((TESTS_PASSED++)) || true
else
    echo "✗ post-session.sh is not executable"
    ((TESTS_FAILED++)) || true
fi

# 構文チェック
bash -n "$SCRIPT_DIR/../scripts/post-session.sh" 2>/dev/null
exit_code=$?
assert_success "post-session.sh has valid syntax" "$exit_code"

# ヘルプ表示
output=$("$SCRIPT_DIR/../scripts/post-session.sh" --help 2>&1)
exit_code=$?
assert_success "post-session.sh --help exits with 0" "$exit_code"
assert_contains "post-session.sh --help shows usage" "Usage:" "$output"
assert_contains "post-session.sh --help shows --auto option" "--auto" "$output"
assert_contains "post-session.sh --help shows --worktree option" "--worktree" "$output"
assert_contains "post-session.sh --help shows --session option" "--session" "$output"

# 引数なしで実行（エラーになるべき）
output=$("$SCRIPT_DIR/../scripts/post-session.sh" 2>&1)
exit_code=$?
assert_failure "post-session.sh without arguments fails" "$exit_code"
assert_contains "post-session.sh without arguments shows error" "Issue number is required" "$output"

# ===================
# オプションパースのテスト
# ===================
echo ""
echo "=== Option parsing tests ==="

# 不明なオプション
output=$("$SCRIPT_DIR/../scripts/post-session.sh" --unknown-option 2>&1)
exit_code=$?
assert_failure "post-session.sh with unknown option fails" "$exit_code"
assert_contains "post-session.sh shows error for unknown option" "Unknown option" "$output"

# ===================
# run.sh のオプションテスト
# ===================
echo ""
echo "=== run.sh option tests ==="

# run.shの構文チェック
bash -n "$SCRIPT_DIR/../scripts/run.sh" 2>/dev/null
exit_code=$?
assert_success "run.sh has valid syntax" "$exit_code"

# ヘルプに--auto-cleanupが含まれているか
output=$("$SCRIPT_DIR/../scripts/run.sh" --help 2>&1)
assert_contains "run.sh --help shows --auto-cleanup option" "--auto-cleanup" "$output"
assert_contains "run.sh --help shows --no-cleanup option" "--no-cleanup" "$output"

# ===================
# lib/tmux.sh create_session テスト
# ===================
echo ""
echo "=== lib/tmux.sh create_session tests ==="

# tmux.shの構文チェック
bash -n "$SCRIPT_DIR/../lib/tmux.sh" 2>/dev/null
exit_code=$?
assert_success "lib/tmux.sh has valid syntax" "$exit_code"

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
