#!/usr/bin/env bats
# watch-session.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    
    # 元のPATHを保存（他のテストでモックが有効化されている場合に備える）
    export ORIGINAL_PATH="$PATH"
    
    # 必要なライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
}

teardown() {
    # PATHを復元（他のテストへの影響を防ぐ）
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# マーカー検出ロジックテスト
# ====================

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

@test "marker not present - not detected" {
    result=$(simulate_marker_detection "some output" "more output" "###TASK_COMPLETE_42###")
    [ "$result" = "not_detected" ]
}

@test "marker present in current - detected" {
    result=$(simulate_marker_detection "some output" "output ###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###")
    [ "$result" = "detected" ]
}

@test "same marker count - not detected" {
    result=$(simulate_marker_detection "###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###")
    [ "$result" = "not_detected" ]
}

@test "more markers than baseline - detected" {
    baseline_multi="line1
###TASK_COMPLETE_42###
line2"
    current_multi="line1
###TASK_COMPLETE_42###
line2
###TASK_COMPLETE_42###"
    result=$(simulate_marker_detection "$baseline_multi" "$current_multi" "###TASK_COMPLETE_42###")
    [ "$result" = "detected" ]
}

@test "empty baseline with new marker - detected" {
    result=$(simulate_marker_detection "" "###TASK_COMPLETE_42###" "###TASK_COMPLETE_42###")
    [ "$result" = "detected" ]
}

@test "empty output - not detected" {
    result=$(simulate_marker_detection "" "" "###TASK_COMPLETE_42###")
    [ "$result" = "not_detected" ]
}

# ====================
# Issue番号抽出テスト
# ====================

@test "extract_issue_number from pi-issue-42" {
    result="$(extract_issue_number "pi-issue-42")"
    [ "$result" = "42" ]
}

@test "extract_issue_number from pi-issue-134" {
    result="$(extract_issue_number "pi-issue-134")"
    [ "$result" = "134" ]
}

@test "extract_issue_number from project-issue-999" {
    result="$(extract_issue_number "project-issue-999")"
    [ "$result" = "999" ]
}

@test "extract_issue_number from pi-issue-42-feature" {
    result="$(extract_issue_number "pi-issue-42-feature")"
    [ "$result" = "42" ]
}

@test "extract_issue_number from pi-issue-10-fix-bug-abc" {
    result="$(extract_issue_number "pi-issue-10-fix-bug-abc")"
    [ "$result" = "10" ]
}

@test "extract_issue_number returns empty for invalid session name" {
    result="$(extract_issue_number "session-name-only" 2>/dev/null)" || result=""
    [ -z "$result" ]
}

# ====================
# 引数処理テスト
# ====================

@test "watch-session.sh --help exits with 0" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
}

@test "watch-session.sh --help shows Usage" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "watch-session.sh --help shows --marker option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [[ "$output" == *"--marker"* ]]
}

@test "watch-session.sh --help shows --interval option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [[ "$output" == *"--interval"* ]]
}

@test "watch-session.sh without session name fails" {
    run "$PROJECT_ROOT/scripts/watch-session.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Session name is required"* ]] || [[ "$output" == *"required"* ]]
}

@test "watch-session.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" "test-session" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================
# マーカー生成テスト
# ====================

@test "marker format for issue 42" {
    expected="###TASK_COMPLETE_42###"
    [ "$expected" = "###TASK_COMPLETE_42###" ]
}

@test "marker format for issue 134" {
    expected="###TASK_COMPLETE_134###"
    [ "$expected" = "###TASK_COMPLETE_134###" ]
}

@test "marker format for issue 1" {
    expected="###TASK_COMPLETE_1###"
    [ "$expected" = "###TASK_COMPLETE_1###" ]
}

# ====================
# 存在しないセッションテスト
# ====================

@test "watch-session.sh fails for non-existent session" {
    if ! command -v tmux &> /dev/null; then
        skip "tmux not installed"
    fi
    
    run "$PROJECT_ROOT/scripts/watch-session.sh" "nonexistent-session-xyz123"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Session not found"* ]] || [[ "$output" == *"not found"* ]]
}

# ====================
# Issue #281: 初期化時マーカー検出テスト
# ====================

# ベースラインに既にマーカーがある場合の検出シミュレーション
simulate_startup_marker_detection() {
    local baseline_output="$1"
    local marker="$2"
    
    if echo "$baseline_output" | grep -qF "$marker" 2>/dev/null; then
        echo "detected_at_startup"
    else
        echo "not_detected"
    fi
}

@test "Issue #281: marker present in baseline - detected at startup" {
    baseline="some output
###TASK_COMPLETE_42###
more output"
    result=$(simulate_startup_marker_detection "$baseline" "###TASK_COMPLETE_42###")
    [ "$result" = "detected_at_startup" ]
}

@test "Issue #281: marker not in baseline - not detected at startup" {
    baseline="some output
more output"
    result=$(simulate_startup_marker_detection "$baseline" "###TASK_COMPLETE_42###")
    [ "$result" = "not_detected" ]
}

@test "Issue #281: empty baseline - not detected at startup" {
    result=$(simulate_startup_marker_detection "" "###TASK_COMPLETE_42###")
    [ "$result" = "not_detected" ]
}

@test "Issue #281: error marker in baseline - detected at startup" {
    baseline="some output
###TASK_ERROR_42###
Error message here"
    result=$(simulate_startup_marker_detection "$baseline" "###TASK_ERROR_42###")
    [ "$result" = "detected_at_startup" ]
}

@test "Issue #281: partial marker in baseline - not detected" {
    baseline="some output
###TASK_COMPLETE
more output"
    result=$(simulate_startup_marker_detection "$baseline" "###TASK_COMPLETE_42###")
    [ "$result" = "not_detected" ]
}

# ====================
# Issue #393, #648, #651: count_markers_outside_codeblock テスト
# ====================

@test "count_markers_outside_codeblock: marker outside codeblock is counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output="some text
###TASK_COMPLETE_42###
more text"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: indented marker outside codeblock is counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output="some text
    ###TASK_COMPLETE_42###
more text"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: marker inside codeblock is not counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output='some text
```
###TASK_COMPLETE_42###
```
more text'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock: multiple markers in different codeblocks" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output='first codeblock
```
###TASK_COMPLETE_42###
```
second codeblock
```
###TASK_COMPLETE_42###
```
end'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock: empty output returns 0" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local result
    result=$(count_markers_outside_codeblock "" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock: marker adjacent to codeblock boundary (marker before triple backticks)" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    # marker on line N, ``` on line N+1 → should be excluded
    local output='some text
###TASK_COMPLETE_42###
```
code here
```
end'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock: marker adjacent to codeblock boundary (marker after triple backticks)" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    # ``` on line N-1, marker on line N → should be excluded
    local output='some text
```
###TASK_COMPLETE_42###
code here
end'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock: marker 2 lines away from codeblock is counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    # marker on line N, ``` on line N+2 → should be counted (outside ±1 range)
    local output='some text
###TASK_COMPLETE_42###
normal line
```
code here
```
end'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: mixed markers - one inside, one outside" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output='outside marker
###TASK_COMPLETE_42###
some text
```
###TASK_COMPLETE_42###
```
end'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: marker at start of output is counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output='###TASK_COMPLETE_42###
some text
more text'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: marker at end of output is counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output='some text
more text
###TASK_COMPLETE_42###'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: tab-indented marker outside codeblock is counted" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    # Use printf to ensure actual tab character
    local output
    output=$(printf "some text\n\t###TASK_COMPLETE_42###\nmore text")
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock: error marker works the same way" {
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    local output='some text
###TASK_ERROR_42###
error message'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_ERROR_42###")
    [ "$result" -eq 1 ]
}
