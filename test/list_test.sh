#!/usr/bin/env bash
# list.sh のテスト

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_SCRIPT="$SCRIPT_DIR/../scripts/list.sh"

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
echo "=== list.sh help option tests ==="

# --help オプション
result=$("$LIST_SCRIPT" --help 2>&1)
exit_code=$?
assert_success "--help returns success" "$exit_code"
assert_contains "--help shows usage" "Usage:" "$result"
assert_contains "--help shows verbose option" "--verbose" "$result"
assert_contains "--help shows -v option" "-v" "$result"
assert_contains "--help shows -h option" "-h" "$result"

# -h オプション
result=$("$LIST_SCRIPT" -h 2>&1)
exit_code=$?
assert_success "-h returns success" "$exit_code"
assert_contains "-h shows usage" "Usage:" "$result"

# ===================
# オプションパースのテスト
# ===================
echo ""
echo "=== list.sh option parsing tests ==="

# 不明なオプション
result=$("$LIST_SCRIPT" --unknown-option 2>&1)
exit_code=$?
assert_failure "list.sh with unknown option fails" "$exit_code"
assert_contains "error message mentions unknown option" "Unknown option" "$result"

# ===================
# セッションなしの場合のテスト
# ===================
echo ""
echo "=== list.sh no sessions tests ==="

# セッション一覧ヘッダーの確認
# Note: 実際のセッションがない場合も正常終了するはず
result=$("$LIST_SCRIPT" 2>&1)
exit_code=$?
assert_success "list.sh without sessions returns success" "$exit_code"
assert_contains "output shows header" "Active Pi Issue Sessions" "$result"

# ===================
# スクリプトソースコードの構造テスト
# ===================
echo ""
echo "=== Script structure tests ==="

# スクリプトの構文チェック
bash -n "$LIST_SCRIPT" 2>&1
exit_code=$?
assert_success "list.sh has valid bash syntax" "$exit_code"

# ソースコードの内容確認
list_source=$(cat "$LIST_SCRIPT")

assert_contains "script sources config.sh" "lib/config.sh" "$list_source"
assert_contains "script sources log.sh" "lib/log.sh" "$list_source"
assert_contains "script sources tmux.sh" "lib/tmux.sh" "$list_source"
assert_contains "script sources worktree.sh" "lib/worktree.sh" "$list_source"
assert_contains "script has main function" "main()" "$list_source"
assert_contains "script has usage function" "usage()" "$list_source"
assert_contains "script calls list_sessions" "list_sessions" "$list_source"
assert_contains "script calls get_status_value" "get_status_value" "$list_source"
assert_contains "script has verbose variable" "verbose=" "$list_source"
assert_contains "script has enable_verbose call" "enable_verbose" "$list_source"

# ===================
# verboseモードのロジックテスト
# ===================
echo ""
echo "=== Verbose mode logic tests ==="

assert_contains "script handles -v option" '-v|--verbose)' "$list_source"
assert_contains "script sets verbose to true" 'verbose=true' "$list_source"
assert_contains "script checks verbose mode" 'verbose" == "true"' "$list_source"

# 詳細情報表示の確認
assert_contains "verbose mode shows Session" 'echo "Session:' "$list_source"
assert_contains "verbose mode shows Issue" 'echo "  Issue:' "$list_source"
assert_contains "verbose mode shows Status" 'echo "  Status:' "$list_source"

# ===================
# 出力フォーマットのテスト
# ===================
echo ""
echo "=== Output format tests ==="

# 標準出力にテーブルヘッダーが含まれることを確認
assert_contains "script has SESSION header" "SESSION" "$list_source"
assert_contains "script has ISSUE header" "ISSUE" "$list_source"
assert_contains "script has STATUS header" "STATUS" "$list_source"
assert_contains "script has ERROR header" "ERROR" "$list_source"

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
