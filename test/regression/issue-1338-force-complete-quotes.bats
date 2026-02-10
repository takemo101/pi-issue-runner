#!/usr/bin/env bats
# Regression test for Issue #1338
# force-complete.sh --message with single quotes should not break

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
# クォート処理の検証
# ====================

@test "force-complete.sh uses double-quote escaping for marker (not single quotes)" {
    # マーカー送信がダブルクォートを使用していることを確認
    # シングルクォートで囲む旧パターンが存在しないこと
    run grep -n "send_keys.*echo '.*marker'" "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -ne 0 ]  # マッチしない = シングルクォートパターンがない
}

@test "force-complete.sh uses double-quote escaping for custom_message (not single quotes)" {
    # カスタムメッセージ送信がダブルクォートを使用していることを確認
    run grep -n "send_keys.*echo '.*custom_message'" "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -ne 0 ]  # マッチしない = シングルクォートパターンがない
}

@test "force-complete.sh escapes double quotes in marker" {
    grep -q 'escaped_marker=.*marker.*\\"' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh escapes double quotes in custom_message" {
    grep -q 'escaped_message=.*custom_message.*\\"' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh send_keys uses escaped_marker with double quotes" {
    grep -q 'send_keys.*"echo \\".*escaped_marker' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh send_keys uses escaped_message with double quotes" {
    grep -q 'send_keys.*"echo \\".*escaped_message' "$PROJECT_ROOT/scripts/force-complete.sh"
}

# ====================
# エスケープロジック検証（ユニットテスト的）
# ====================

@test "bash parameter expansion correctly escapes double quotes" {
    # force-complete.shで使用しているエスケープパターンの検証
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
