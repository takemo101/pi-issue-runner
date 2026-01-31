#!/usr/bin/env bash
# notify_test.sh - notify.sh のテスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# テスト用のテンポラリディレクトリ
TEST_TMP_DIR=""

setup() {
    TEST_TMP_DIR="$(mktemp -d)"
    
    # ライブラリを読み込み（先に読み込まないとget_configが使えない）
    source "$SCRIPT_DIR/../lib/config.sh"
    source "$SCRIPT_DIR/../lib/log.sh"
    source "$SCRIPT_DIR/../lib/notify.sh"
    
    # テスト用の設定を上書き（get_config をモック）
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_TMP_DIR/.worktrees" ;;
            *) echo "" ;;
        esac
    }
    
    mkdir -p "$TEST_TMP_DIR/.worktrees"
    
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

assert_file_exists() {
    local description="$1"
    local filepath="$2"
    
    if [[ -f "$filepath" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  File does not exist: $filepath"
        ((TESTS_FAILED++)) || true
    fi
}

assert_dir_exists() {
    local description="$1"
    local dirpath="$2"
    
    if [[ -d "$dirpath" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Directory does not exist: $dirpath"
        ((TESTS_FAILED++)) || true
    fi
}

assert_file_contains() {
    local description="$1"
    local filepath="$2"
    local pattern="$3"
    
    if grep -q "$pattern" "$filepath" 2>/dev/null; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Pattern '$pattern' not found in $filepath"
        ((TESTS_FAILED++)) || true
    fi
}

# テスト実行
echo "=== notify.sh tests ==="
echo ""

# セットアップ
setup

# --- get_status_dir テスト ---
echo "--- get_status_dir ---"
status_dir="$(get_status_dir)"
expected_status_dir="$TEST_TMP_DIR/.worktrees/.status"
assert_equals "get_status_dir returns correct path" "$expected_status_dir" "$status_dir"

# --- init_status_dir テスト ---
echo ""
echo "--- init_status_dir ---"
init_status_dir
assert_dir_exists "init_status_dir creates directory" "$status_dir"

# --- save_status テスト ---
echo ""
echo "--- save_status ---"
save_status "42" "running" "pi-issue-42"
assert_file_exists "save_status creates status file" "$status_dir/42.json"
assert_file_contains "save_status writes issue number" "$status_dir/42.json" '"issue": 42'
assert_file_contains "save_status writes status" "$status_dir/42.json" '"status": "running"'
assert_file_contains "save_status writes session" "$status_dir/42.json" '"session": "pi-issue-42"'

# --- save_status with error ---
echo ""
echo "--- save_status with error ---"
save_status "43" "error" "pi-issue-43" "Test error message"
assert_file_exists "save_status creates error status file" "$status_dir/43.json"
assert_file_contains "save_status writes error_message" "$status_dir/43.json" '"error_message":'
assert_file_contains "save_status writes error message content" "$status_dir/43.json" 'Test error message'
assert_file_contains "save_status writes error status" "$status_dir/43.json" '"status": "error"'

# --- load_status テスト ---
echo ""
echo "--- load_status ---"
json="$(load_status "42")"
assert_file_contains "load_status returns valid JSON" <(echo "$json") '"issue": 42'

# --- get_status_value テスト ---
echo ""
echo "--- get_status_value ---"
status_value="$(get_status_value "42")"
assert_equals "get_status_value returns running" "running" "$status_value"

status_value="$(get_status_value "43")"
assert_equals "get_status_value returns error" "error" "$status_value"

status_value="$(get_status_value "999")"
assert_equals "get_status_value returns unknown for non-existent" "unknown" "$status_value"

# --- get_error_message テスト ---
echo ""
echo "--- get_error_message ---"
error_msg="$(get_error_message "43")"
# トリムして比較（tr '\n' ' 'による末尾スペースを考慮）
error_msg_trimmed="${error_msg%% }"
assert_equals "get_error_message returns error message" "Test error message" "$error_msg_trimmed"

error_msg="$(get_error_message "42")"
assert_equals "get_error_message returns empty for non-error" "" "$error_msg"

# --- remove_status テスト ---
echo ""
echo "--- remove_status ---"
remove_status "42"
status_value="$(get_status_value "42")"
assert_equals "remove_status removes file" "unknown" "$status_value"

# --- is_macos / is_linux テスト ---
echo ""
echo "--- platform detection ---"
if [[ "$(uname)" == "Darwin" ]]; then
    if is_macos; then
        echo "✓ is_macos returns true on macOS"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ is_macos should return true on macOS"
        ((TESTS_FAILED++)) || true
    fi
    
    if ! is_linux; then
        echo "✓ is_linux returns false on macOS"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ is_linux should return false on macOS"
        ((TESTS_FAILED++)) || true
    fi
elif [[ "$(uname)" == "Linux" ]]; then
    if is_linux; then
        echo "✓ is_linux returns true on Linux"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ is_linux should return true on Linux"
        ((TESTS_FAILED++)) || true
    fi
    
    if ! is_macos; then
        echo "✓ is_macos returns false on Linux"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ is_macos should return false on Linux"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "⚠ Skipping platform detection tests (unknown platform: $(uname))"
fi

# --- JSON escape テスト ---
echo ""
echo "--- JSON escape in save_status ---"
save_status "44" "error" "pi-issue-44" 'Error with "quotes" and \backslash'
json_content="$(cat "$status_dir/44.json")"
# JSONが有効かチェック（jqがあれば）
if command -v jq &>/dev/null; then
    if echo "$json_content" | jq . > /dev/null 2>&1; then
        echo "✓ JSON with special chars is valid"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ JSON with special chars is invalid"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "⚠ Skipping JSON validation (jq not installed)"
fi

# クリーンアップ
teardown

# 結果表示
echo ""
echo "=== Results ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

exit $TESTS_FAILED
