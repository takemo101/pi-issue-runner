#!/usr/bin/env bash
# config.sh のテスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

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

# ===================
# 重複呼び出し防止テスト
# ===================
echo "=== _CONFIG_LOADED flag tests ==="

_CONFIG_LOADED=""
load_config
assert_equals "_CONFIG_LOADED is set after load_config" "true" "$_CONFIG_LOADED"

# 2回目の呼び出しでも問題ないことを確認
load_config
assert_equals "_CONFIG_LOADED remains true after second call" "true" "$_CONFIG_LOADED"

# ===================
# デフォルト値テスト
# ===================
echo ""
echo "=== Default values tests ==="

_CONFIG_LOADED=""
unset PI_RUNNER_WORKTREE_BASE_DIR 2>/dev/null || true
unset PI_RUNNER_TMUX_SESSION_PREFIX 2>/dev/null || true
CONFIG_WORKTREE_BASE_DIR=".worktrees"
CONFIG_TMUX_SESSION_PREFIX="pi"

load_config
assert_equals "default worktree_base_dir" ".worktrees" "$(get_config worktree_base_dir)"
assert_equals "default tmux_session_prefix" "pi" "$(get_config tmux_session_prefix)"

# ===================
# 環境変数オーバーライドテスト
# ===================
echo ""
echo "=== Environment variable override tests ==="

_CONFIG_LOADED=""
export PI_RUNNER_WORKTREE_BASE_DIR="custom_worktrees"
export PI_RUNNER_TMUX_SESSION_PREFIX="custom_prefix"

load_config
assert_equals "env override worktree_base_dir" "custom_worktrees" "$(get_config worktree_base_dir)"
assert_equals "env override tmux_session_prefix" "custom_prefix" "$(get_config tmux_session_prefix)"

unset PI_RUNNER_WORKTREE_BASE_DIR
unset PI_RUNNER_TMUX_SESSION_PREFIX

# ===================
# 配列の先頭スペーステスト
# ===================
echo ""
echo "=== Array parsing tests ==="

# 設定ファイルをテスト用に作成
TEST_CONFIG=$(mktemp)
cat > "$TEST_CONFIG" << 'EOF'
worktree:
  base_dir: ".test-worktrees"
  copy_files:
    - ".env"
    - ".env.local"
    - ".envrc"

pi:
  command: "pi"
  args:
    - "--verbose"
    - "--model"
    - "gpt-4"
EOF

_CONFIG_LOADED=""
CONFIG_WORKTREE_COPY_FILES=""
CONFIG_PI_ARGS=""

load_config "$TEST_CONFIG"

# 先頭スペースがないことを確認
copy_files="$(get_config worktree_copy_files)"
if [[ "$copy_files" == " "* ]]; then
    echo "✗ copy_files has leading space: '$copy_files'"
    ((TESTS_FAILED++)) || true
else
    echo "✓ copy_files has no leading space"
    ((TESTS_PASSED++)) || true
fi

pi_args="$(get_config pi_args)"
if [[ "$pi_args" == " "* ]]; then
    echo "✗ pi_args has leading space: '$pi_args'"
    ((TESTS_FAILED++)) || true
else
    echo "✓ pi_args has no leading space"
    ((TESTS_PASSED++)) || true
fi

assert_equals "copy_files parsed correctly" ".env .env.local .envrc" "$copy_files"
assert_equals "pi_args parsed correctly" "--verbose --model gpt-4" "$pi_args"

rm -f "$TEST_CONFIG"

# ===================
# reload_config テスト
# ===================
echo ""
echo "=== reload_config tests ==="

_CONFIG_LOADED="true"
reload_config
assert_equals "reload_config resets and reloads" "true" "$_CONFIG_LOADED"

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
