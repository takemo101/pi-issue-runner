#!/usr/bin/env bash
# ci-monitor.sh - CI状態監視機能
#
# このライブラリはCIの状態監視とポーリング機能を提供します。

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CI_MONITOR_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_MONITOR_SH_SOURCED="true"

_CI_MONITOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CI_MONITOR_LIB_DIR/log.sh"
source "$_CI_MONITOR_LIB_DIR/github.sh"

# ===================
# 定数定義
# ===================

# CIポーリング設定
CI_POLL_INTERVAL=30      # ポーリング間隔（秒）
CI_TIMEOUT=600           # タイムアウト（10分 = 600秒）

# ===================
# CI状態監視
# ===================

# CI完了を待機（ポーリング）
# Usage: wait_for_ci_completion <pr_number> [timeout_seconds]
# Returns: 0=成功, 1=失敗, 2=タイムアウト
wait_for_ci_completion() {
    local pr_number="$1"
    local timeout="${2:-$CI_TIMEOUT}"
    local elapsed=0
    
    log_info "Waiting for CI completion (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(get_pr_checks_status "$pr_number" 2>/dev/null || echo "pending")
        
        case "$status" in
            "success")
                log_info "CI completed successfully"
                return 0
                ;;
            "failure")
                log_warn "CI failed"
                return 1
                ;;
            *)
                log_debug "CI status: $status (elapsed: ${elapsed}s)"
                ;;
        esac
        
        sleep "$CI_POLL_INTERVAL"
        elapsed=$((elapsed + CI_POLL_INTERVAL))
    done
    
    log_error "CI wait timed out after ${timeout}s"
    return 2
}

# PRのCIチェック状態を取得
# Usage: get_pr_checks_status <pr_number>
# Returns: success | failure | pending | unknown
get_pr_checks_status() {
    local pr_number="$1"
    
    if ! command -v gh &> /dev/null; then
        log_error "gh CLI not found"
        echo "unknown"
        return 1
    fi
    
    # PRのチェック状態を取得
    local checks_json
    checks_json=$(gh pr checks "$pr_number" --json state 2>/dev/null || echo "[]")
    
    # チェックがない場合は成功とみなす
    if [[ -z "$checks_json" || "$checks_json" == "[]" ]]; then
        echo "success"
        return 0
    fi
    
    # jqで解析
    if command -v jq &> /dev/null; then
        # 失敗があるかチェック
        if echo "$checks_json" | jq -e 'any(.[]; .state == "FAILURE")' > /dev/null 2>&1; then
            echo "failure"
            return 0
        fi
        
        # 進行中があるかチェック
        if echo "$checks_json" | jq -e 'any(.[]; .state == "PENDING" or .state == "QUEUED")' > /dev/null 2>&1; then
            echo "pending"
            return 0
        fi
        
        # 全て成功
        if echo "$checks_json" | jq -e 'all(.[]; .state == "SUCCESS")' > /dev/null 2>&1; then
            echo "success"
            return 0
        fi
    fi
    
    echo "unknown"
    return 0
}
