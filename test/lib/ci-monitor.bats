#!/usr/bin/env bats
# ci-monitor.bats - CI状態監視機能のテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/ci-monitor.sh"
}

teardown() {
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# 定数テスト
# ===================

@test "ci-monitor constants are defined correctly" {
    [[ "$CI_POLL_INTERVAL" == "30" ]]
    [[ "$CI_TIMEOUT" == "600" ]]
}

# ===================
# get_pr_checks_status テスト
# ===================

@test "get_pr_checks_status returns error when gh CLI is not available" {
    # ghコマンドがない場合、エラーステータスと"unknown"を返す
    # 注: このテストは gh がインストールされている環境ではスキップ
    if command -v gh &> /dev/null; then
        skip "gh CLI is installed - cannot test missing CLI scenario"
    fi
    
    run get_pr_checks_status 123
    [ "$status" -eq 1 ]
    [ "$output" == "unknown" ]
}

@test "get_pr_checks_status function exists" {
    declare -f get_pr_checks_status
}

@test "wait_for_ci_completion function exists" {
    declare -f wait_for_ci_completion
}

# ===================
# タイムアウト処理テスト（シミュレーション）
# ===================

@test "CI_TIMEOUT constant is numeric" {
    [[ "$CI_TIMEOUT" =~ ^[0-9]+$ ]]
}

@test "CI_POLL_INTERVAL constant is numeric" {
    [[ "$CI_POLL_INTERVAL" =~ ^[0-9]+$ ]]
}

@test "CI_POLL_INTERVAL is less than CI_TIMEOUT" {
    [[ "$CI_POLL_INTERVAL" -lt "$CI_TIMEOUT" ]]
}
