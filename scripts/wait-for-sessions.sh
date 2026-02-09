#!/usr/bin/env bash
# ============================================================================
# wait-for-sessions.sh - Wait for multiple sessions to complete
#
# Waits for all specified issue sessions to complete by monitoring
# status files (.worktrees/.status/<issue>.json).
#
# Usage: ./scripts/wait-for-sessions.sh <issue-number>... [options]
#
# Arguments:
#   issue-number...   Issue numbers to wait for (multiple allowed)
#
# Options:
#   --timeout <sec>   Timeout in seconds (default: 3600 = 1 hour)
#   --interval <sec>  Check interval in seconds (default: 5)
#   --fail-fast       Exit immediately if any session errors
#   --cleanup         Auto-cleanup worktrees after completion
#   --quiet           Suppress progress display
#   -h, --help        Show help message
#
# Exit codes:
#   0 - All sessions completed successfully
#   1 - One or more sessions failed
#   2 - Timeout
#   3 - Argument error
#
# Examples:
#   ./scripts/wait-for-sessions.sh 140 141 144
#   ./scripts/wait-for-sessions.sh 140 141 --timeout 1800
#   ./scripts/wait-for-sessions.sh 140 141 --fail-fast
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/tmux.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number>... [options]

Arguments:
    issue-number...   待機するIssue番号（複数指定可）

Options:
    --timeout <sec>   タイムアウト秒数（デフォルト: 3600 = 1時間）
    --interval <sec>  チェック間隔（デフォルト: 5秒）
    --fail-fast       1つでもエラーになったら即座に終了
    --cleanup         完了したセッションのworktreeを自動クリーンアップ
    --quiet           進捗表示を抑制
    -h, --help        このヘルプを表示

Description:
    指定したIssue番号のセッションがすべて完了するまで待機します。
    ステータスファイル (.worktrees/.status/<issue>.json) を監視し、
    全セッションが complete になったら正常終了します。

Examples:
    $(basename "$0") 140 141 144
    $(basename "$0") 140 141 --timeout 1800
    $(basename "$0") 140 141 --fail-fast
    $(basename "$0") 140 141 --cleanup

Exit codes:
    0 - 全セッションが正常完了
    1 - 1つ以上のセッションがエラー
    2 - タイムアウト
    3 - 引数エラー
EOF
}

main() {
    local -a issues=()
    local timeout=3600
    local interval=5
    local fail_fast=false
    local cleanup=false
    local quiet=false

    # 引数のパース
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --fail-fast)
                fail_fast=true
                shift
                ;;
            --cleanup)
                cleanup=true
                shift
                ;;
            --quiet|-q)
                quiet=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 3
                ;;
            *)
                # 数字のみ許可
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    issues+=("$1")
                else
                    log_error "Invalid issue number: $1"
                    exit 3
                fi
                shift
                ;;
        esac
    done

    if [[ ${#issues[@]} -eq 0 ]]; then
        log_error "At least one issue number is required"
        usage >&2
        exit 3
    fi

    load_config

    if [[ "$quiet" != "true" ]]; then
        log_info "Waiting for ${#issues[@]} session(s): ${issues[*]}"
        log_info "Timeout: ${timeout}s, Check interval: ${interval}s"
        if [[ "$cleanup" == "true" ]]; then
            log_info "Auto-cleanup enabled"
        fi
    fi

    wait_for_sessions "${issues[@]}"
}

# Run auto-cleanup for a completed/errored issue
# Usage: _run_issue_cleanup <issue>
_run_issue_cleanup() {
    local issue="$1"

    if [[ "$cleanup" == "true" ]]; then
        if [[ "$quiet" != "true" ]]; then
            echo "    Cleaning up worktree for Issue #$issue..."
        fi
        "$SCRIPT_DIR/cleanup.sh" "pi-issue-$issue" --force 2>/dev/null || true
    fi
}

# Process a single issue's status in the wait loop
# Usage: process_issue_status <issue> <completed_list_var> <errored_list_var> <all_done_var> <has_error_var>
# Returns: 0 normally, 1 if fail-fast triggered
process_issue_status() {
    local issue="$1"
    local -n _completed_ref="$2"
    local -n _errored_ref="$3"
    local -n _all_done_ref="$4"
    local -n _has_error_ref="$5"

    # 既に完了/エラー判定済みはスキップ
    if echo " $_completed_ref " | grep -q " $issue "; then
        return 0
    fi
    if echo " $_errored_ref " | grep -q " $issue "; then
        return 0
    fi

    local status
    status="$(get_status "$issue")"

    case "$status" in
        complete)
            _completed_ref="$_completed_ref $issue"
            if [[ "$quiet" != "true" ]]; then
                echo "[✓] Issue #$issue 完了"
            fi
            _run_issue_cleanup "$issue"
            ;;
        error)
            _errored_ref="$_errored_ref $issue"
            _has_error_ref=true
            local error_msg
            error_msg="$(get_error_message "$issue")"
            if [[ "$quiet" != "true" ]]; then
                echo "[✗] Issue #$issue エラー: $error_msg"
            fi
            _run_issue_cleanup "$issue"
            if [[ "$fail_fast" == "true" ]]; then
                log_error "Fail-fast enabled. Exiting due to error in issue #$issue"
                return 1
            fi
            ;;
        running)
            _all_done_ref=false
            ;;
        unknown)
            # tmuxセッションが存在するか確認
            local session_name="pi-issue-$issue"
            if session_exists "$session_name"; then
                # セッションはあるがステータス不明 → まだ開始中
                _all_done_ref=false
            else
                # セッションがない → 完了済みとして扱う
                _completed_ref="$_completed_ref $issue"
                if [[ "$quiet" != "true" ]]; then
                    echo "[✓] Issue #$issue 完了（セッション終了済み）"
                fi
                _run_issue_cleanup "$issue"
            fi
            ;;
    esac
    return 0
}

# Check if all sessions are done and report results
# Usage: check_completion_status <all_done> <has_error> <errored_list> <issues_str>
# Returns: 0 if all done successfully, 1 if errors, 255 if not all done yet
check_completion_status() {
    local all_done="$1"
    local has_error="$2"
    local errored_list="$3"
    local issues_str="$4"

    if [[ "$all_done" != "true" ]]; then
        return 255  # Not done yet
    fi

    if [[ "$has_error" == "true" ]]; then
        local error_count
        error_count=$(echo "$errored_list" | wc -w | tr -d ' ')
        if [[ "$quiet" != "true" ]]; then
            log_error "$error_count session(s) failed"
        fi
        return 1
    fi

    local total_count
    total_count=$(echo "$issues_str" | wc -w | tr -d ' ')
    if [[ "$quiet" != "true" ]]; then
        log_info "All $total_count session(s) completed successfully"
    fi
    return 0
}

# Check if timeout has been reached
# Usage: check_wait_timeout <start_time> <issues_str> <completed_list> <errored_list>
# Returns: 0 if not timed out, 2 if timed out
check_wait_timeout() {
    local start_time="$1"
    local issues_str="$2"
    local completed_list="$3"
    local errored_list="$4"

    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [[ $elapsed -ge $timeout ]]; then
        local running_count=0
        for issue in $issues_str; do
            if ! echo " $completed_list " | grep -q " $issue " && ! echo " $errored_list " | grep -q " $issue "; then
                ((running_count++)) || true
            fi
        done
        if [[ "$quiet" != "true" ]]; then
            log_error "Timeout after ${elapsed}s. $running_count session(s) still running."
        fi
        return 2
    fi

    # 進捗表示（verboseモード）
    if [[ "$quiet" != "true" ]] && [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
        local completed_count
        local errored_count
        local total
        completed_count=$(echo "$completed_list" | wc -w | tr -d ' ')
        errored_count=$(echo "$errored_list" | wc -w | tr -d ' ')
        total=$(echo "$issues_str" | wc -w | tr -d ' ')
        log_debug "Progress: $completed_count/$total complete, $errored_count errors, ${elapsed}s elapsed"
    fi

    return 0
}

# セッション完了を待機
# 引数: Issue番号の配列
# 戻り値: 0=全完了, 1=エラー発生, 2=タイムアウト
wait_for_sessions() {
    local issues_str="$*"
    local start_time
    start_time=$(date +%s)

    # 完了/エラー済みのIssueをスペース区切りで保持（Bash 3.x互換）
    local completed_list=""
    local errored_list=""

    while true; do
        local all_done=true
        local has_error=false

        for issue in $issues_str; do
            if ! process_issue_status "$issue" completed_list errored_list all_done has_error; then
                return 1  # fail-fast triggered
            fi
        done

        # 全て完了判定
        local status_result=0
        check_completion_status "$all_done" "$has_error" "$errored_list" "$issues_str" || status_result=$?
        if [[ $status_result -ne 255 ]]; then
            return $status_result
        fi

        # タイムアウトチェック
        local timeout_result=0
        check_wait_timeout "$start_time" "$issues_str" "$completed_list" "$errored_list" || timeout_result=$?
        if [[ $timeout_result -ne 0 ]]; then
            return $timeout_result
        fi

        sleep "$interval"
    done
}

main "$@"
