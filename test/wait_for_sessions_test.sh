#!/usr/bin/env bash
# wait_for_sessions_test.sh - wait-for-sessions.sh のテスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."

# テスト用のテンポラリディレクトリ
TEST_TMP_DIR=""

setup() {
    TEST_TMP_DIR="$(mktemp -d)"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    # テスト用の設定を上書き
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_TMP_DIR/.worktrees" ;;
            *) echo "" ;;
        esac
    }
    
    mkdir -p "$TEST_TMP_DIR/.worktrees/.status"
    
    # ログを抑制
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# テスト結果カウンター
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

assert_exit_code() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected exit code: $expected"
        echo "  Actual exit code:   $actual"
        ((TESTS_FAILED++)) || true
    fi
}

# テスト実行
echo "=== wait-for-sessions.sh tests ==="
echo ""

# セットアップ
setup

# --- ヘルプ表示テスト ---
echo "--- help display ---"
help_output=$("$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help 2>&1) || true
if echo "$help_output" | grep -q "Usage:"; then
    echo "✓ --help shows usage"
    ((TESTS_PASSED++)) || true
else
    echo "✗ --help should show usage"
    ((TESTS_FAILED++)) || true
fi

# --- 引数なしエラーテスト ---
echo ""
echo "--- no arguments error ---"
set +e
"$PROJECT_ROOT/scripts/wait-for-sessions.sh" 2>/dev/null
exit_code=$?
set -e
assert_exit_code "No arguments returns exit code 3" "3" "$exit_code"

# --- 不正なIssue番号エラーテスト ---
echo ""
echo "--- invalid issue number error ---"
set +e
"$PROJECT_ROOT/scripts/wait-for-sessions.sh" "abc" 2>/dev/null
exit_code=$?
set -e
assert_exit_code "Invalid issue number returns exit code 3" "3" "$exit_code"

# --- すべて完了済みのテスト ---
echo ""
echo "--- all sessions complete ---"

# テスト用ステータスディレクトリを設定
export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_TMP_DIR/.worktrees"

# 完了ステータスを作成
mkdir -p "$TEST_TMP_DIR/.worktrees/.status"
cat > "$TEST_TMP_DIR/.worktrees/.status/200.json" << 'EOF'
{
  "issue": 200,
  "status": "complete",
  "session": "pi-issue-200",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

cat > "$TEST_TMP_DIR/.worktrees/.status/201.json" << 'EOF'
{
  "issue": 201,
  "status": "complete",
  "session": "pi-issue-201",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

set +e
output=$("$PROJECT_ROOT/scripts/wait-for-sessions.sh" 200 201 --interval 1 --timeout 5 --quiet 2>&1)
exit_code=$?
set -e
assert_exit_code "All complete returns exit code 0" "0" "$exit_code"

# --- エラーセッションのテスト ---
echo ""
echo "--- session with error ---"

cat > "$TEST_TMP_DIR/.worktrees/.status/300.json" << 'EOF'
{
  "issue": 300,
  "status": "error",
  "session": "pi-issue-300",
  "error_message": "Test error",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

set +e
output=$("$PROJECT_ROOT/scripts/wait-for-sessions.sh" 300 --interval 1 --timeout 5 --quiet 2>&1)
exit_code=$?
set -e
assert_exit_code "Error session returns exit code 1" "1" "$exit_code"

# --- タイムアウトテスト ---
echo ""
echo "--- timeout test ---"

# 実行中のままのステータス
cat > "$TEST_TMP_DIR/.worktrees/.status/400.json" << 'EOF'
{
  "issue": 400,
  "status": "running",
  "session": "pi-issue-400",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

set +e
output=$("$PROJECT_ROOT/scripts/wait-for-sessions.sh" 400 --interval 1 --timeout 2 --quiet 2>&1)
exit_code=$?
set -e
assert_exit_code "Timeout returns exit code 2" "2" "$exit_code"

# --- fail-fast テスト ---
echo ""
echo "--- fail-fast test ---"

cat > "$TEST_TMP_DIR/.worktrees/.status/500.json" << 'EOF'
{
  "issue": 500,
  "status": "running",
  "session": "pi-issue-500",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

cat > "$TEST_TMP_DIR/.worktrees/.status/501.json" << 'EOF'
{
  "issue": 501,
  "status": "error",
  "session": "pi-issue-501",
  "error_message": "Immediate failure",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

set +e
output=$("$PROJECT_ROOT/scripts/wait-for-sessions.sh" 500 501 --interval 1 --timeout 10 --fail-fast --quiet 2>&1)
exit_code=$?
set -e
assert_exit_code "Fail-fast returns exit code 1 immediately" "1" "$exit_code"

# --- 混合ステータステスト ---
echo ""
echo "--- mixed status (complete + error) ---"

cat > "$TEST_TMP_DIR/.worktrees/.status/600.json" << 'EOF'
{
  "issue": 600,
  "status": "complete",
  "session": "pi-issue-600",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

cat > "$TEST_TMP_DIR/.worktrees/.status/601.json" << 'EOF'
{
  "issue": 601,
  "status": "error",
  "session": "pi-issue-601",
  "error_message": "Failed",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

set +e
output=$("$PROJECT_ROOT/scripts/wait-for-sessions.sh" 600 601 --interval 1 --timeout 5 --quiet 2>&1)
exit_code=$?
set -e
assert_exit_code "Mixed status (complete + error) returns exit code 1" "1" "$exit_code"

# クリーンアップ
unset PI_RUNNER_WORKTREE_BASE_DIR
teardown

# 結果表示
echo ""
echo "=== Results ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

exit $TESTS_FAILED
