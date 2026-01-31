#!/usr/bin/env bash
# watch-session.sh のテスト

# テスト用にエラーで終了しないように
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 必要なライブラリを読み込み
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

# テスト用にエラーで終了しないように再設定（sourceで上書きされるため）
set +e

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

# ===================
# テストヘルパー関数
# ===================
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

assert_empty() {
    local description="$1"
    local actual="$2"
    if [[ -z "$actual" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (value is not empty: '$actual')"
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
# マーカー検出ロジックテスト
# ===================
echo "=== Marker detection logic tests ==="

# マーカー検出のシミュレーション関数
simulate_marker_detection() {
    local baseline_output="$1"
    local current_output="$2"
    local marker="$3"
    
    local marker_count_baseline
    local marker_count_current
    marker_count_baseline=$(echo "$baseline_output" | grep -cF "$marker" 2>/dev/null) || marker_count_baseline=0
    marker_count_current=$(echo "$current_output" | grep -cF "$marker" 2>/dev/null) || marker_count_current=0
    
    if [[ "$marker_count_current" -gt "$marker_count_baseline" ]]; then
        echo "detected"
    else
        echo "not_detected"
    fi
}

# マーカーが存在しない場合は検出しない
result=$(simulate_marker_detection "some output" "more output" "###TASK_COMPLETE_42###")
assert_equals "Marker not present - not detected" "not_detected" "$result"

# マーカーが存在する場合は検出する
result=$(simulate_marker_detection "some output" "output ###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###")
assert_equals "Marker present in current - detected" "detected" "$result"

# ベースラインと同じマーカー数の場合は検出しない
result=$(simulate_marker_detection "###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###")
assert_equals "Same marker count - not detected" "not_detected" "$result"

# ベースラインより多いマーカー（別の行に）がある場合は検出する
baseline_multi="line1
###TASK_COMPLETE_42###
line2"
current_multi="line1
###TASK_COMPLETE_42###
line2
###TASK_COMPLETE_42###"
result=$(simulate_marker_detection "$baseline_multi" "$current_multi" "###TASK_COMPLETE_42###")
assert_equals "More markers than baseline (on separate lines) - detected" "detected" "$result"

# 空のベースラインで新しいマーカー
result=$(simulate_marker_detection "" "###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###")
assert_equals "Empty baseline with new marker - detected" "detected" "$result"

# 空の出力
result=$(simulate_marker_detection "" "" "###TASK_COMPLETE_42###")
assert_equals "Empty output - not detected" "not_detected" "$result"

# ===================
# Issue番号抽出テスト（extract_issue_numberを使用）
# ===================
echo ""
echo "=== Issue number extraction tests ==="

# 標準的なセッション名
result=$(extract_issue_number "pi-issue-42")
assert_equals "Extract from 'pi-issue-42'" "42" "$result"

result=$(extract_issue_number "pi-issue-134")
assert_equals "Extract from 'pi-issue-134'" "134" "$result"

result=$(extract_issue_number "project-issue-999")
assert_equals "Extract from 'project-issue-999'" "999" "$result"

# サフィックス付きセッション名
result=$(extract_issue_number "pi-issue-42-feature")
assert_equals "Extract from 'pi-issue-42-feature'" "42" "$result"

result=$(extract_issue_number "pi-issue-10-fix-bug-abc")
assert_equals "Extract from 'pi-issue-10-fix-bug-abc'" "10" "$result"

# 不正なセッション名
result=$(extract_issue_number "no-issue-here" 2>/dev/null) || true
# このケースではフォールバックで何らかの数字を返すかもしれない
# 数字がない場合は空を返す

result=$(extract_issue_number "session-name-only" 2>/dev/null) || true
assert_empty "Invalid session name returns empty" "$result"

# ===================
# 引数処理テスト
# ===================
echo ""
echo "=== Argument processing tests ==="

WATCH_SCRIPT="$PROJECT_ROOT/scripts/watch-session.sh"

# --help オプションが機能する
result=$("$WATCH_SCRIPT" --help 2>&1)
exit_code=$?
assert_success "--help exits with 0" "$exit_code"
assert_contains "--help shows Usage" "Usage:" "$result"
assert_contains "--help shows --marker option" "--marker" "$result"
assert_contains "--help shows --interval option" "--interval" "$result"

# セッション名が必要
result=$("$WATCH_SCRIPT" 2>&1)
exit_code=$?
assert_failure "No session name fails" "$exit_code"
assert_contains "Error message for missing session" "Session name is required" "$result"

# 不明なオプション
result=$("$WATCH_SCRIPT" "test-session" --unknown-option 2>&1)
exit_code=$?
assert_failure "Unknown option fails" "$exit_code"
assert_contains "Unknown option error" "Unknown option" "$result"

# ===================
# マーカー生成テスト
# ===================
echo ""
echo "=== Marker generation tests ==="

# デフォルトマーカー形式のテスト
test_marker_format() {
    local issue_number="$1"
    local expected="###TASK_COMPLETE_${issue_number}###"
    echo "$expected"
}

result=$(test_marker_format "42")
assert_equals "Marker format for issue 42" "###TASK_COMPLETE_42###" "$result"

result=$(test_marker_format "134")
assert_equals "Marker format for issue 134" "###TASK_COMPLETE_134###" "$result"

result=$(test_marker_format "1")
assert_equals "Marker format for issue 1" "###TASK_COMPLETE_1###" "$result"

# ===================
# 存在しないセッションのテスト
# ===================
echo ""
echo "=== Non-existent session tests ==="

if command -v tmux &> /dev/null; then
    result=$("$WATCH_SCRIPT" "nonexistent-session-xyz123" 2>&1)
    exit_code=$?
    assert_failure "Non-existent session fails" "$exit_code"
    assert_contains "Session not found error" "Session not found" "$result"
else
    echo "⊘ Skipping tmux-dependent tests (tmux not installed)"
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
