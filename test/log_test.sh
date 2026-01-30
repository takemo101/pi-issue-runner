#!/usr/bin/env bash
# log.sh のテスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log.sh"

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

assert_not_contains() {
    local description="$1"
    local pattern="$2"
    local actual="$3"
    if [[ "$actual" != *"$pattern"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Should not contain: '$pattern'"
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
# ログ出力テスト
# ===================
echo "=== Log output tests ==="

LOG_LEVEL="INFO"
output=$(log_info "Test message" 2>&1)
assert_contains "log_info includes INFO" "[INFO]" "$output"
assert_contains "log_info includes message" "Test message" "$output"
assert_contains "log_info includes timestamp format" "$(date '+%Y-%m-%d')" "$output"

output=$(log_error "Error message" 2>&1)
assert_contains "log_error includes ERROR" "[ERROR]" "$output"

output=$(log_warn "Warning message" 2>&1)
assert_contains "log_warn includes WARN" "[WARN]" "$output"

# ===================
# ログレベルテスト
# ===================
echo ""
echo "=== Log level tests ==="

LOG_LEVEL="INFO"
output=$(log_debug "Debug message" 2>&1)
assert_equals "DEBUG hidden when level is INFO" "" "$output"

LOG_LEVEL="DEBUG"
output=$(log_debug "Debug message" 2>&1)
assert_contains "DEBUG shown when level is DEBUG" "[DEBUG]" "$output"

LOG_LEVEL="ERROR"
output=$(log_info "Info message" 2>&1)
assert_equals "INFO hidden when level is ERROR" "" "$output"

output=$(log_error "Error message" 2>&1)
assert_contains "ERROR shown when level is ERROR" "[ERROR]" "$output"

# ===================
# set_log_level テスト
# ===================
echo ""
echo "=== set_log_level tests ==="

set_log_level "DEBUG"
assert_equals "set_log_level DEBUG" "DEBUG" "$LOG_LEVEL"

set_log_level "WARN"
assert_equals "set_log_level WARN" "WARN" "$LOG_LEVEL"

set_log_level "INVALID" 2>/dev/null
assert_equals "invalid level defaults to INFO" "INFO" "$LOG_LEVEL"

# ===================
# enable_verbose/quiet テスト
# ===================
echo ""
echo "=== verbose/quiet tests ==="

enable_verbose
assert_equals "enable_verbose sets DEBUG" "DEBUG" "$LOG_LEVEL"

enable_quiet
assert_equals "enable_quiet sets ERROR" "ERROR" "$LOG_LEVEL"

# ===================
# 関数存在テスト
# ===================
echo ""
echo "=== Function existence tests ==="

for func in log log_debug log_info log_warn log_error set_log_level \
            enable_verbose enable_quiet setup_cleanup_trap \
            cleanup_worktree_on_error register_worktree_for_cleanup; do
    if declare -f "$func" > /dev/null 2>&1; then
        echo "✓ $func exists"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $func does not exist"
        ((TESTS_FAILED++)) || true
    fi
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
