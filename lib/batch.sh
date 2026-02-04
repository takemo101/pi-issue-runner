#!/usr/bin/env bash
# batch.sh - バッチ処理のコア機能
#
# このライブラリは scripts/run-batch.sh から分割された機能を提供します。
# グローバル変数への依存:
#   - QUIET, SEQUENTIAL, CONTINUE_ON_ERROR - 動作モード制御
#   - TIMEOUT, INTERVAL - タイムアウト設定
#   - WORKFLOW_NAME, BASE_BRANCH - 実行設定
#   - FAILED_ISSUES, COMPLETED_ISSUES - 結果追跡（配列）
#   - SCRIPT_DIR - run.sh のパス解決用

set -euo pipefail

_BATCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_BATCH_LIB_DIR/log.sh"
source "$_BATCH_LIB_DIR/status.sh"
source "$_BATCH_LIB_DIR/dependency.sh"

# Issueを実行（同期的）
# 引数: issue_number
# 戻り値: 0=成功, 1=失敗
execute_issue() {
    local issue_number="$1"

    if [[ "${QUIET:-false}" != "true" ]]; then
        log_info "Starting pi-issue-$issue_number..."
    fi

    local run_script
    run_script="${SCRIPT_DIR}/run.sh"

    if [[ "${QUIET:-false}" != "true" ]]; then
        "$run_script" "$issue_number" \
            --workflow "$WORKFLOW_NAME" \
            --base "$BASE_BRANCH" \
            --no-attach \
            --ignore-blockers
    else
        "$run_script" "$issue_number" \
            --workflow "$WORKFLOW_NAME" \
            --base "$BASE_BRANCH" \
            --no-attach \
            --ignore-blockers > /dev/null 2>&1
    fi
}

# Issueを実行（非同期）
# 引数: issue_number
execute_issue_async() {
    local issue_number="$1"

    local run_script
    run_script="${SCRIPT_DIR}/run.sh"

    # バックグラウンドで実行
    (
        "$run_script" "$issue_number" \
            --workflow "$WORKFLOW_NAME" \
            --base "$BASE_BRANCH" \
            --no-attach \
            --ignore-blockers > /dev/null 2>&1
    ) &
}

# レイヤーの完了を待機
# 引数: Issue番号の配列
# グローバル変数を更新: FAILED_ISSUES, COMPLETED_ISSUES
# 戻り値: 0=全成功, 1=一部失敗
wait_for_layer_completion() {
    local -a issues=("$@")
    local start_time
    start_time=$(date +%s)

    while true; do
        local all_done=true
        local has_layer_error=false

        for issue in "${issues[@]}"; do
            local status
            status="$(get_status "$issue")"

            case "$status" in
                complete)
                    # shellcheck disable=SC2076
                    if [[ ! " ${COMPLETED_ISSUES[*]} " =~ " $issue " ]]; then
                        COMPLETED_ISSUES+=("$issue")
                    fi
                    ;;
                error)
                    # shellcheck disable=SC2076
                    if [[ ! " ${FAILED_ISSUES[*]} " =~ " $issue " ]]; then
                        FAILED_ISSUES+=("$issue")
                    fi
                    has_layer_error=true
                    ;;
                running|unknown)
                    all_done=false
                    ;;
            esac
        done

        if [[ "$all_done" == "true" ]]; then
            if [[ "$has_layer_error" == "true" ]]; then
                return 1
            fi
            return 0
        fi

        # タイムアウトチェック
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -ge ${TIMEOUT:-3600} ]]; then
            log_error "Timeout after ${elapsed}s"
            return 1
        fi

        sleep "${INTERVAL:-5}"
    done
}

# レイヤー内のIssueを順次実行
# 引数: layer_issue_array（可変長）
# グローバル変数を更新: FAILED_ISSUES, COMPLETED_ISSUES
# 戻り値: 0=成功, 1=失敗
execute_layer_sequential() {
    local -a layer_issue_array=("$@")

    for issue in "${layer_issue_array[@]}"; do
        if ! execute_issue "$issue"; then
            FAILED_ISSUES+=("$issue")
            if [[ "${CONTINUE_ON_ERROR:-false}" != "true" ]]; then
                log_error "Issue #$issue failed, aborting"
                return 1
            fi
        else
            COMPLETED_ISSUES+=("$issue")
        fi
    done

    return 0
}

# レイヤー内のIssueを並列実行
# 引数: layer_issue_array（可変長）
# グローバル変数を更新: FAILED_ISSUES, COMPLETED_ISSUES
# 戻り値: 0=成功, 1=失敗
execute_layer_parallel() {
    local -a layer_issue_array=("$@")

    # 並列実行
    for issue in "${layer_issue_array[@]}"; do
        if [[ "${QUIET:-false}" != "true" ]]; then
            log_info "Starting pi-issue-$issue..."
        fi
        execute_issue_async "$issue"
    done

    # 完了待機
    if [[ "${QUIET:-false}" != "true" ]]; then
        log_info "Waiting for completion..."
    fi

    if ! wait_for_layer_completion "${layer_issue_array[@]}"; then
        if [[ "${CONTINUE_ON_ERROR:-false}" != "true" ]]; then
            log_error "Layer failed, aborting"
            return 1
        fi
    fi

    return 0
}

# レイヤーを実行
# 引数: current_layer, layers_output
# 戻り値: 0=成功, 1=失敗, 2=スキップ（空レイヤー）
process_layer() {
    local current_layer="$1"
    local layers_output="$2"

    # 現在のレイヤーのIssueを取得
    local layer_issues
    layer_issues="$(echo "$layers_output" | awk -v layer="$current_layer" '$1 == layer {print $2}')"

    if [[ -z "$layer_issues" ]]; then
        return 2  # スキップ
    fi

    # レイヤー内のIssueを配列に変換
    local -a layer_issue_array=()
    while IFS= read -r issue; do
        [[ -n "$issue" ]] && layer_issue_array+=("$issue")
    done <<< "$layer_issues"

    if [[ ${#layer_issue_array[@]} -eq 0 ]]; then
        return 2  # スキップ
    fi

    # レイヤー開始表示
    if [[ "${QUIET:-false}" != "true" ]]; then
        local issue_list=""
        for issue in "${layer_issue_array[@]}"; do
            issue_list="$issue_list #$issue"
        done
        log_info ""
        log_info "=== Layer $current_layer:${issue_list} ==="
    fi

    # 実行
    if [[ "${SEQUENTIAL:-false}" == "true" ]] || [[ ${#layer_issue_array[@]} -eq 1 ]]; then
        if ! execute_layer_sequential "${layer_issue_array[@]}"; then
            return 1
        fi
    else
        if ! execute_layer_parallel "${layer_issue_array[@]}"; then
            return 1
        fi
    fi

    if [[ "${QUIET:-false}" != "true" ]]; then
        log_info "✓ Layer $current_layer completed"
    fi

    return 0
}

# 結果サマリーを表示して終了
# グローバル変数を参照: ALL_ISSUES, FAILED_ISSUES
# 戻り値: 0=全成功, 1=一部失敗（exitで終了）
show_summary_and_exit() {
    echo ""
    if [[ ${#FAILED_ISSUES[@]} -gt 0 ]]; then
        log_error "${#FAILED_ISSUES[@]} issue(s) failed: ${FAILED_ISSUES[*]}"
        echo ""
        echo "Failed issues:"
        for issue in "${FAILED_ISSUES[@]}"; do
            echo "  - #$issue"
        done
        exit 1
    else
        log_info "✅ All ${#ALL_ISSUES[@]} issues completed successfully"
        exit 0
    fi
}
