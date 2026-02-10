#!/usr/bin/env bats
# Regression test for Issue #1338
# force-complete.sh is now deprecated (redirects to stop.sh --cleanup)
# Original issue: --message with single quotes should not break
# These tests verify the deprecation wrapper and remaining relevant behavior.

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    unset _CONFIG_LOADED
    unset _MUX_TYPE
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# 廃止ラッパーの検証（Issue #1392: force-complete.sh → stop.sh --cleanup）
# ====================

@test "force-complete.sh uses double-quote escaping for marker (not single quotes)" {
    # Deprecated script no longer sends markers directly; just ensure no
    # single-quote send_keys pattern exists
    run grep -n "send_keys.*echo '.*marker'" "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -ne 0 ]  # マッチしない = シングルクォートパターンがない
}

@test "force-complete.sh uses double-quote escaping for custom_message (not single quotes)" {
    # Deprecated script no longer sends messages directly
    run grep -n "send_keys.*echo '.*custom_message'" "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -ne 0 ]  # マッチしない = シングルクォートパターンがない
}

@test "force-complete.sh is now a deprecation wrapper" {
    # force-complete.sh should redirect to stop.sh --cleanup
    grep -q 'exec.*stop.sh' "$PROJECT_ROOT/scripts/force-complete.sh"
    grep -q '\-\-cleanup' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh shows deprecation warning" {
    grep -q 'WARNING.*deprecated' "$PROJECT_ROOT/scripts/force-complete.sh"
}

# ====================
# エスケープロジック検証（ユニットテスト的）
# ====================

@test "bash parameter expansion correctly escapes double quotes" {
    # force-complete.shで使用していたエスケープパターンの検証
    local input='Said "hello" world'
    local escaped="${input//\"/\\\"}"
    [ "$escaped" = 'Said \"hello\" world' ]
}

@test "bash parameter expansion leaves single quotes intact" {
    # シングルクォートはダブルクォート内では特殊文字ではないため、そのまま
    local input="User's task is done"
    local escaped="${input//\"/\\\"}"
    [ "$escaped" = "User's task is done" ]
}

@test "bash parameter expansion handles mixed quotes" {
    local input="User's \"task\" is done"
    local escaped="${input//\"/\\\"}"
    [ "$escaped" = "User's \\\"task\\\" is done" ]
}

@test "marker format does not contain problematic characters" {
    # マーカーは ###TASK_COMPLETE_N### 形式で、クォートを含まない
    local issue_number=42
    local marker="###TASK_COMPLETE_${issue_number}###"
    local escaped="${marker//\"/\\\"}"
    # エスケープ前後で変化なし（ダブルクォートを含まないため）
    [ "$marker" = "$escaped" ]
}
