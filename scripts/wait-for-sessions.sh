#!/usr/bin/env bash
# wait-for-sessions.sh - 複数セッションの完了を待機

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/status.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number>... [options]

Arguments:
    issue-number...   待機するIssue番号（複数指定可）

Options:
    --timeout <sec>   タイムアウト秒数（デフォルト: 3600 = 1時間）
    --interval <sec>  チェック間隔（デフォルト: 5秒）
    --fail-fast       1つでもエラーになったら即座に終了
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
    fi

    wait_for_sessions "${issues[@]}"
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
            # 既に完了/エラー判定済みはスキップ
            if echo " $completed_list " | grep -q " $issue "; then
                continue
            fi
            if echo " $errored_list " | grep -q " $issue "; then
                continue
            fi
            
            local status
            status="$(get_status "$issue")"
            
            case "$status" in
                complete)
                    completed_list="$completed_list $issue"
                    if [[ "$quiet" != "true" ]]; then
                        echo "[✓] Issue #$issue 完了"
                    fi
                    ;;
                error)
                    errored_list="$errored_list $issue"
                    has_error=true
                    local error_msg
                    error_msg="$(get_error_message "$issue")"
                    if [[ "$quiet" != "true" ]]; then
                        echo "[✗] Issue #$issue エラー: $error_msg"
                    fi
                    if [[ "$fail_fast" == "true" ]]; then
                        log_error "Fail-fast enabled. Exiting due to error in issue #$issue"
                        return 1
                    fi
                    ;;
                running)
                    all_done=false
                    ;;
                unknown)
                    # tmuxセッションが存在するか確認
                    local session_name="pi-issue-$issue"
                    if tmux has-session -t "$session_name" 2>/dev/null; then
                        # セッションはあるがステータス不明 → まだ開始中
                        all_done=false
                    else
                        # セッションがない → 完了済みとして扱う
                        completed_list="$completed_list $issue"
                        if [[ "$quiet" != "true" ]]; then
                            echo "[✓] Issue #$issue 完了（セッション終了済み）"
                        fi
                    fi
                    ;;
            esac
        done
        
        # 全て完了判定
        if [[ "$all_done" == "true" ]]; then
            if [[ "$has_error" == "true" ]]; then
                # エラー数をカウント
                local error_count
                error_count=$(echo "$errored_list" | wc -w | tr -d ' ')
                if [[ "$quiet" != "true" ]]; then
                    log_error "$error_count session(s) failed"
                fi
                return 1
            fi
            # 完了数をカウント
            local total_count
            total_count=$(echo "$issues_str" | wc -w | tr -d ' ')
            if [[ "$quiet" != "true" ]]; then
                log_info "All $total_count session(s) completed successfully"
            fi
            return 0
        fi
        
        # タイムアウトチェック
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
        
        sleep "$interval"
    done
}

main "$@"
