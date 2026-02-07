#!/usr/bin/env bash
# ci-retry.sh - CI自動修正リトライ管理機能
#
# このライブラリはCI失敗自動修正のリトライ回数管理を提供します。

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CI_RETRY_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_RETRY_SH_SOURCED="true"

_CI_RETRY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CI_RETRY_LIB_DIR/log.sh"
source "$_CI_RETRY_LIB_DIR/status.sh"

# ===================
# 定数定義
# ===================

MAX_RETRY_COUNT=3        # 最大リトライ回数

# ===================
# リトライ管理
# ===================

# リトライ状態ファイルのパスを取得
# Usage: get_retry_state_file <issue_number>
get_retry_state_file() {
    local issue_number="$1"
    local state_dir
    if [[ -n "${PI_RUNNER_STATE_DIR:-}" ]]; then
        state_dir="$PI_RUNNER_STATE_DIR"
    else
        # status.sh と同じディレクトリに保存
        state_dir="$(get_status_dir)"
    fi
    mkdir -p "$state_dir"
    echo "$state_dir/ci-retry-$issue_number"
}

# リトライ回数を取得
# Usage: get_retry_count <issue_number>
get_retry_count() {
    local issue_number="$1"
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# リトライ回数をインクリメント
# Usage: increment_retry_count <issue_number>
increment_retry_count() {
    local issue_number="$1"
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    local count
    count=$(get_retry_count "$issue_number")
    
    echo $((count + 1)) > "$state_file"
}

# リトライ回数をリセット
# Usage: reset_retry_count <issue_number>
reset_retry_count() {
    local issue_number="$1"
    local state_file
    state_file=$(get_retry_state_file "$issue_number")
    
    rm -f "$state_file"
}

# リトライを続行すべきか判定
# Usage: should_continue_retry <issue_number>
# Returns: 0=続行可能, 1=最大回数に達した
should_continue_retry() {
    local issue_number="$1"
    local count
    count=$(get_retry_count "$issue_number")
    
    if [[ $count -lt $MAX_RETRY_COUNT ]]; then
        log_info "Retry attempt $((count + 1))/$MAX_RETRY_COUNT"
        return 0
    else
        log_warn "Maximum retry count ($MAX_RETRY_COUNT) reached"
        return 1
    fi
}
