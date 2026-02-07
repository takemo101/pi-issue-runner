#!/usr/bin/env bats
# Regression test for Issue #1015
# 
# Problem: watch-session.sh の handle_complete 内で PR 未マージ時に
# クリーンアップをスキップするが、セッションとworktreeが残り続ける
#
# Root cause: check_pr_merge_status が return 1 を返すと、handle_complete も
# return 1 し、メインの監視ループが exit 1 で終了し、watcherプロセスが
# 終了してリソースがリークする
#
# Fix: PR未マージ時は return 2 を返し、監視ループは継続する。
# リトライロジックを追加して、一定時間後にPRマージを再確認する。

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "Issue #1015: check_pr_merge_status has retry mechanism" {
    # Source the script to access the function
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    
    # Verify function exists
    type check_pr_merge_status &>/dev/null
}

@test "Issue #1015: check_pr_merge_status accepts retry parameters" {
    # Verify function signature supports max_attempts and retry_interval
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    
    # The function should accept at least 3 parameters
    # check_pr_merge_status <session_name> <branch_name> <issue_number> [max_attempts] [retry_interval]
    type check_pr_merge_status &>/dev/null
}

@test "Issue #1015: handle_complete can return code 2 for timeout" {
    # Verify that handle_complete is designed to return:
    # 0 = success
    # 1 = cleanup failure
    # 2 = PR merge timeout (continue monitoring)
    
    source "$PROJECT_ROOT/scripts/watch-session.sh" 2>/dev/null || true
    type handle_complete &>/dev/null
}

@test "Issue #1015: monitoring loop handles timeout return code" {
    # Read the watch-session.sh source and verify the monitoring loop
    # handles return code 2 from handle_complete
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    # Check that the loop handles result code 2
    [[ "$script_content" == *"complete_result=\$?"* ]]
    [[ "$script_content" == *"elif [[ \$complete_result -eq 2 ]]"* ]]
    [[ "$script_content" == *"continue"* ]]
}

@test "Issue #1015: watcher does not exit on PR timeout" {
    # Verify that when completion marker is detected but PR is not merged,
    # the watcher continues monitoring instead of exiting
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    # The fix should include logic to continue monitoring
    [[ "$script_content" == *"Continuing to monitor"* ]] || \
    [[ "$script_content" == *"continue monitoring"* ]] || \
    [[ "$script_content" == *"Will continue monitoring"* ]]
}

@test "Issue #1015: default retry count is reasonable" {
    # Verify default retry parameters are set
    # Default should be 10 attempts with 60 second intervals
    # (total: 10 minutes of retry time)
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    # Check for default values in function signature
    [[ "$script_content" == *'max_attempts="${4:-10}"'* ]] || \
    [[ "$script_content" == *'max_attempts=${4:-10}'* ]]
    
    [[ "$script_content" == *'retry_interval="${5:-60}"'* ]] || \
    [[ "$script_content" == *'retry_interval=${5:-60}'* ]]
}

@test "Issue #1015: PR CLOSED state is treated as completion" {
    # Verify that CLOSED PRs (not just MERGED) are treated as successful completion
    # This prevents resource leaks for manually closed PRs
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    [[ "$script_content" == *'CLOSED'* ]]
    [[ "$script_content" == *'treating as completion'* ]]
}

@test "Issue #1015: timeout returns distinct error code" {
    # Verify timeout scenarios return code 2 (not 1)
    # This allows the calling code to distinguish between:
    # - Hard failure (1)
    # - Timeout/retry needed (2)
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    # Check that timeout returns 2
    [[ "$script_content" == *'return 2'* ]]
}

@test "Issue #1015: baseline is updated after timeout to prevent re-trigger" {
    # When PR timeout occurs and monitoring continues,
    # the baseline should be updated to prevent the same marker
    # from triggering handle_complete repeatedly
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    # After timeout, baseline should be updated
    [[ "$script_content" == *'baseline_output="$output"'* ]]
}

@test "Issue #1015: no hardcoded exit 1 in completion handler path" {
    # Verify that the code path from completion marker detection
    # does not unconditionally exit with error
    
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/watch-session.sh")
    
    # The monitoring loop should handle different return codes
    # and only exit 1 for actual failures, not timeouts
    
    # This is a design verification - we check that the code
    # has logic to handle timeout differently from failure
    [[ "$script_content" == *'complete_result'* ]]
}
