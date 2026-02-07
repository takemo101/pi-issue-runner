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
