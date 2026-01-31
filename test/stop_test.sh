#!/usr/bin/env bash
# stop.sh のテスト

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP_SCRIPT="$SCRIPT_DIR/../scripts/stop.sh"

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
# ヘルプオプションのテスト
# ===================
echo "=== stop.sh help option tests ==="

# --help オプション
result=$("$STOP_SCRIPT" --help 2>&1)
exit_code=$?
assert_success "--help returns success" "$exit_code"
assert_contains "--help shows usage" "Usage:" "$result"
assert_contains "--help shows session-name argument" "session-name" "$result"
assert_contains "--help shows issue-number argument" "issue-number" "$result"
assert_contains "--help shows examples" "Examples:" "$result"
assert_contains "--help shows pi-issue-42 example" "pi-issue-42" "$result"
assert_contains "--help shows 42 example" "42" "$result"

# -h オプション
result=$("$STOP_SCRIPT" -h 2>&1)
exit_code=$?
assert_success "-h returns success" "$exit_code"
assert_contains "-h shows usage" "Usage:" "$result"

# ===================
# エラーケースのテスト
# ===================
echo ""
echo "=== stop.sh error cases tests ==="

# 引数なしで実行
result=$("$STOP_SCRIPT" 2>&1)
exit_code=$?
assert_failure "stop.sh without argument fails" "$exit_code"
assert_contains "error message mentions session/issue required" "required" "$result"

# 不明なオプション
result=$("$STOP_SCRIPT" --unknown-option 2>&1)
exit_code=$?
assert_failure "stop.sh with unknown option fails" "$exit_code"
assert_contains "error message mentions unknown option" "Unknown option" "$result"

# ===================
# セッション名生成テスト
# ===================
echo ""
echo "=== Session name generation tests ==="

# ライブラリを読み込んでセッション名生成をテスト
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

# デフォルト設定でテスト
_CONFIG_LOADED=""
load_config

result=$(generate_session_name "42")
assert_contains "session name contains issue number" "42" "$result"
assert_contains "session name contains 'issue'" "issue" "$result"

# 数字のみの入力がセッション名に変換されることを確認
result=$(generate_session_name "999")
assert_contains "session name for 999" "999" "$result"

# ===================
# スクリプトソースコードの構造テスト
# ===================
echo ""
echo "=== Script structure tests ==="

# スクリプトの構文チェック
bash -n "$STOP_SCRIPT" 2>&1
exit_code=$?
assert_success "stop.sh has valid bash syntax" "$exit_code"

# ソースコードの内容確認
stop_source=$(cat "$STOP_SCRIPT")

assert_contains "script sources config.sh" "lib/config.sh" "$stop_source"
assert_contains "script sources log.sh" "lib/log.sh" "$stop_source"
assert_contains "script sources tmux.sh" "lib/tmux.sh" "$stop_source"
assert_contains "script has main function" "main()" "$stop_source"
assert_contains "script has usage function" "usage()" "$stop_source"
assert_contains "script calls generate_session_name" "generate_session_name" "$stop_source"
assert_contains "script calls kill_session" "kill_session" "$stop_source"
assert_contains "script checks for numeric input" '[0-9]' "$stop_source"

# ===================
# Issue番号からセッション名への変換ロジックテスト
# ===================
echo ""
echo "=== Issue number to session name logic tests ==="

# スクリプトがIssue番号を正しく処理することを確認
assert_contains "script handles numeric issue number" 'if [[ "$target" =~ ^[0-9]+$ ]]' "$stop_source"

# ===================
# セッション停止ロジックのテスト
# ===================
echo ""
echo "=== Session stop logic tests ==="

# kill_session呼び出しの確認
assert_contains "script calls kill_session with session_name" 'kill_session "$session_name"' "$stop_source"

# ログ出力の確認
assert_contains "script logs session stopped" "Session stopped" "$stop_source"

# ===================
# 結果サマリー
# ===================
echo ""
echo "===================="
echo "Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "===================="

exit $TESTS_FAILED
