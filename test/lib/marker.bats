#!/usr/bin/env bats
# test/lib/marker.bats - Tests for marker.sh

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    
    source "$PROJECT_ROOT/lib/marker.sh"
}

teardown() {
    if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "count_markers_outside_codeblock counts simple marker" {
    local output="###TASK_COMPLETE_42###"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock ignores marker in code block" {
    local output='```
###TASK_COMPLETE_42###
```'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock counts marker before code block" {
    local output='###TASK_COMPLETE_42###
```
code here
```'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock counts marker after code block" {
    local output='```
code here
```
###TASK_COMPLETE_42###'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles multiple markers mixed" {
    local output='###TASK_COMPLETE_42###
Some text
```
###TASK_COMPLETE_42###
```
More text
###TASK_COMPLETE_42###'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 2 ]
}

@test "count_markers_outside_codeblock returns 0 when no markers" {
    local output="No markers here"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock handles empty output" {
    local output=""
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock handles indented markers" {
    local output="  ###TASK_COMPLETE_42###"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles different marker types" {
    local output="###TASK_ERROR_42###"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_ERROR_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock ignores partial matches" {
    local output="This is not a ###TASK_COMPLETE_42### marker"
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock ignores marker in multi-line code block" {
    local output='```bash
echo "start"
###TASK_COMPLETE_42###
echo "end"
```'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock counts marker between code blocks" {
    local output='```
code block 1
```
###TASK_COMPLETE_42###
```
code block 2
```'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles multiple code blocks correctly" {
    local output='###TASK_COMPLETE_42###
```
code block 1
###TASK_COMPLETE_42###
```
###TASK_COMPLETE_42###
```
code block 2
###TASK_COMPLETE_42###
```
###TASK_COMPLETE_42###'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 3 ]
}

@test "count_markers_outside_codeblock handles indented code blocks" {
    local output='  ```
  ###TASK_COMPLETE_42###
  ```'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock handles code block with language specifier" {
    local output='```javascript
const x = 1;
###TASK_COMPLETE_42###
console.log(x);
```'
    local result
    result=$(count_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

# 回帰テスト: 正規表現メタ文字を含むマーカーの安全な処理
@test "count_markers_outside_codeblock handles marker with regex metacharacters (dots)" {
    local output="...MARKER..."
    local result
    result=$(count_markers_outside_codeblock "$output" "...MARKER...")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles marker with regex metacharacters (asterisks)" {
    local output="***MARKER***"
    local result
    result=$(count_markers_outside_codeblock "$output" "***MARKER***")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles marker with regex metacharacters (plus)" {
    local output="+++MARKER+++"
    local result
    result=$(count_markers_outside_codeblock "$output" "+++MARKER+++")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles marker with regex metacharacters (parentheses)" {
    local output="(MARKER)"
    local result
    result=$(count_markers_outside_codeblock "$output" "(MARKER)")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles marker with regex metacharacters (brackets)" {
    local output="[MARKER]"
    local result
    result=$(count_markers_outside_codeblock "$output" "[MARKER]")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock handles marker with regex metacharacters (question mark)" {
    local output="MARKER?"
    local result
    result=$(count_markers_outside_codeblock "$output" "MARKER?")
    [ "$result" -eq 1 ]
}

@test "count_markers_outside_codeblock does not match similar marker with dots" {
    local output="...MARKER..."
    local result
    # Should NOT match "XXXMARKERXXX" (different number of characters)
    result=$(count_markers_outside_codeblock "$output" "XXXMARKERXXX")
    [ "$result" -eq 0 ]
}

@test "count_markers_outside_codeblock handles marker with mixed metacharacters" {
    local output="  [**MARKER**(42)]  "
    local result
    result=$(count_markers_outside_codeblock "$output" "[**MARKER**(42)]")
    [ "$result" -eq 1 ]
}

# count_any_markers_outside_codeblock tests

@test "count_any_markers_outside_codeblock counts single marker" {
    local output="###TASK_COMPLETE_42###
some text"
    local result
    result=$(count_any_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###")
    [ "$result" -eq 1 ]
}

@test "count_any_markers_outside_codeblock counts multiple marker patterns" {
    local output="###COMPLETE_TASK_42###
some text"
    local result
    result=$(count_any_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###" "###COMPLETE_TASK_42###")
    [ "$result" -eq 1 ]
}

@test "count_any_markers_outside_codeblock sums counts from both patterns" {
    local output="###TASK_COMPLETE_42###
some text
###COMPLETE_TASK_42###"
    local result
    result=$(count_any_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###" "###COMPLETE_TASK_42###")
    [ "$result" -eq 2 ]
}

@test "count_any_markers_outside_codeblock returns 0 when no match" {
    local output="some text without markers"
    local result
    result=$(count_any_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###" "###COMPLETE_TASK_42###")
    [ "$result" -eq 0 ]
}

# grep_marker_count_in_file tests

@test "grep_marker_count_in_file returns count for single marker" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' "line1" "###TASK_COMPLETE_42###" "line3" "###TASK_COMPLETE_42###" > "$file"
    local result
    result=$(grep_marker_count_in_file "$file" "###TASK_COMPLETE_42###")
    [ "$result" -eq 2 ]
}

@test "grep_marker_count_in_file returns 0 for missing file" {
    local result
    result=$(grep_marker_count_in_file "/nonexistent/file" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

@test "grep_marker_count_in_file sums counts for multiple markers" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' "###TASK_COMPLETE_42###" "###COMPLETE_TASK_42###" "other line" > "$file"
    local result
    result=$(grep_marker_count_in_file "$file" "###TASK_COMPLETE_42###" "###COMPLETE_TASK_42###")
    [ "$result" -eq 2 ]
}

@test "grep_marker_count_in_file returns 0 when no match" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' "no markers here" "just text" > "$file"
    local result
    result=$(grep_marker_count_in_file "$file" "###TASK_COMPLETE_42###")
    [ "$result" -eq 0 ]
}

# verify_marker_outside_codeblock tests

@test "verify_marker_outside_codeblock returns 0 for marker outside code block (file)" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' "some text" "###TASK_COMPLETE_42###" "more text" > "$file"
    verify_marker_outside_codeblock "$file" "###TASK_COMPLETE_42###" "true"
}

@test "verify_marker_outside_codeblock returns 1 for marker inside code block (file)" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' '```' "###TASK_COMPLETE_42###" '```' > "$file"
    run verify_marker_outside_codeblock "$file" "###TASK_COMPLETE_42###" "true"
    [ "$status" -ne 0 ]
}

@test "verify_marker_outside_codeblock returns 1 for missing marker (file)" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' "no markers" > "$file"
    run verify_marker_outside_codeblock "$file" "###TASK_COMPLETE_42###" "true"
    [ "$status" -ne 0 ]
}

@test "verify_marker_outside_codeblock works with text input" {
    local text="some text
###TASK_COMPLETE_42###
more text"
    verify_marker_outside_codeblock "$text" "###TASK_COMPLETE_42###" "false"
}

@test "verify_marker_outside_codeblock strips ANSI codes from file" {
    local file="$BATS_TEST_TMPDIR/test.log"
    printf '%s\n' "some text" $'\x1b[32m###TASK_COMPLETE_42###\x1b[0m' "more text" > "$file"
    verify_marker_outside_codeblock "$file" "###TASK_COMPLETE_42###" "true"
}

# strip_ansi tests

@test "strip_ansi removes ANSI escape sequences" {
    local result
    result=$(printf '\x1b[32mhello\x1b[0m' | strip_ansi)
    [ "$result" = "hello" ]
}

@test "strip_ansi removes carriage returns" {
    local result
    result=$(printf 'hello\rworld' | strip_ansi)
    [ "$result" = "helloworld" ]
}

@test "count_any_markers_outside_codeblock ignores markers in code blocks" {
    local output="\`\`\`
###COMPLETE_TASK_42###
\`\`\`"
    local result
    result=$(count_any_markers_outside_codeblock "$output" "###TASK_COMPLETE_42###" "###COMPLETE_TASK_42###")
    [ "$result" -eq 0 ]
}
