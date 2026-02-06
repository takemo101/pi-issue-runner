#!/usr/bin/env bash
# batch.sh - バッチ処理のコア機能
#
# このライブラリは scripts/run-batch.sh から分割された機能を提供します。
#
# アーキテクチャ:
#   - グローバル変数に依存せず、全て関数引数で設定を受け取ります
#   - 可変状態（配列）は nameref で明示的に渡します
#   - 設定は連想配列として構造化されています
#
# 使用例:
#   declare -A config=(
#       [quiet]=false
#       [sequential]=false
#       [continue_on_error]=false
#       [timeout]=3600
#       [interval]=5
#       [workflow_name]="default"
#       [base_branch]="HEAD"
#       [script_dir]="/path/to/scripts"
#   )
#   declare -a failed_issues=()
#   declare -a completed_issues=()
#   
#   execute_issue config 42
#   process_layer failed_issues completed_issues config 0 "$layers_output"

set -euo pipefail

_BATCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_BATCH_LIB_DIR/log.sh"
source "$_BATCH_LIB_DIR/status.sh"
source "$_BATCH_LIB_DIR/dependency.sh"

# Issueを実行（同期的）
# 引数:
#   $1: config への参照（連想配列）
#   $2: issue_number
# 戻り値: 0=成功, 1=失敗
execute_issue() {
    local -n _config_ref="$1"
    local issue_number="$2"

    local quiet="${_config_ref[quiet]}"
    local script_dir="${_config_ref[script_dir]}"
    local workflow_name="${_config_ref[workflow_name]}"
    local base_branch="${_config_ref[base_branch]}"

    if [[ "$quiet" != "true" ]]; then
        log_info "Starting pi-issue-$issue_number..."
    fi

    local run_script
    run_script="${script_dir}/run.sh"

    if [[ "$quiet" != "true" ]]; then
        "$run_script" "$issue_number" \
            --workflow "$workflow_name" \
            --base "$base_branch" \
            --no-attach \
            --ignore-blockers
    else
        "$run_script" "$issue_number" \
            --workflow "$workflow_name" \
            --base "$base_branch" \
            --no-attach \
            --ignore-blockers > /dev/null 2>&1
    fi
}

# Issueを実行（非同期）
# 引数:
#   $1: config への参照（連想配列）
#   $2: issue_number
execute_issue_async() {
    local -n _config_ref="$1"
    local issue_number="$2"

    local script_dir="${_config_ref[script_dir]}"
    local workflow_name="${_config_ref[workflow_name]}"
    local base_branch="${_config_ref[base_branch]}"

    local run_script
    run_script="${script_dir}/run.sh"

    # バックグラウンドで実行
    (
        "$run_script" "$issue_number" \
            --workflow "$workflow_name" \
            --base "$base_branch" \
            --no-attach \
            --ignore-blockers > /dev/null 2>&1
    ) &
}

# レイヤーの完了を待機
# 引数:
#   $1: failed_issues への参照（配列）
#   $2: completed_issues への参照（配列）
#   $3: config への参照（連想配列）
#   $4...: Issue番号の配列
# 戻り値: 0=全成功, 1=一部失敗
wait_for_layer_completion() {
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _failed_issues_ref="$1"
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _completed_issues_ref="$2"
    local -n _config_ref="$3"
    shift 3
    local -a issues=("$@")

    local timeout="${_config_ref[timeout]}"
    local interval="${_config_ref[interval]}"

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
                    if [[ ! " ${_completed_issues_ref[*]} " =~ " $issue " ]]; then
                        _completed_issues_ref+=("$issue")
                    fi
                    ;;
                error)
                    # shellcheck disable=SC2076
                    if [[ ! " ${_failed_issues_ref[*]} " =~ " $issue " ]]; then
                        _failed_issues_ref+=("$issue")
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

        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout after ${elapsed}s"
            return 1
        fi

        sleep "$interval"
    done
}

# レイヤー内のIssueを順次実行
# 引数:
#   $1: failed_issues への参照（配列）
#   $2: completed_issues への参照（配列）
#   $3: config への参照（連想配列）
#   $4...: layer_issue_array（可変長）
# 戻り値: 0=成功, 1=失敗
execute_layer_sequential() {
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _failed_issues_ref="$1"
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _completed_issues_ref="$2"
    local -n _config_ref="$3"
    shift 3
    local -a layer_issue_array=("$@")

    local continue_on_error="${_config_ref[continue_on_error]}"

    for issue in "${layer_issue_array[@]}"; do
        if ! execute_issue _config_ref "$issue"; then
            _failed_issues_ref+=("$issue")
            if [[ "$continue_on_error" != "true" ]]; then
                log_error "Issue #$issue failed, aborting"
                return 1
            fi
        else
            _completed_issues_ref+=("$issue")
        fi
    done

    return 0
}

# レイヤー内のIssueを並列実行
# 引数:
#   $1: failed_issues への参照（配列）
#   $2: completed_issues への参照（配列）
#   $3: config への参照（連想配列）
#   $4...: layer_issue_array（可変長）
# 戻り値: 0=成功, 1=失敗
execute_layer_parallel() {
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _failed_issues_ref="$1"
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _completed_issues_ref="$2"
    local -n _config_ref="$3"
    shift 3
    local -a layer_issue_array=("$@")

    local quiet="${_config_ref[quiet]}"
    local continue_on_error="${_config_ref[continue_on_error]}"

    # 並列実行
    for issue in "${layer_issue_array[@]}"; do
        if [[ "$quiet" != "true" ]]; then
            log_info "Starting pi-issue-$issue..."
        fi
        execute_issue_async _config_ref "$issue"
    done

    # 完了待機
    if [[ "$quiet" != "true" ]]; then
        log_info "Waiting for completion..."
    fi

    if ! wait_for_layer_completion _failed_issues_ref _completed_issues_ref _config_ref "${layer_issue_array[@]}"; then
        if [[ "$continue_on_error" != "true" ]]; then
            log_error "Layer failed, aborting"
            return 1
        fi
    fi

    return 0
}

# レイヤーを実行
# 引数:
#   $1: failed_issues への参照（配列）
#   $2: completed_issues への参照（配列）
#   $3: config への参照（連想配列）
#   $4: current_layer
#   $5: layers_output
# 戻り値: 0=成功, 1=失敗, 2=スキップ（空レイヤー）
process_layer() {
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _failed_issues_ref="$1"
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _completed_issues_ref="$2"
    local -n _config_ref="$3"
    local current_layer="$4"
    local layers_output="$5"

    local quiet="${_config_ref[quiet]}"
    local sequential="${_config_ref[sequential]}"

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
    if [[ "$quiet" != "true" ]]; then
        local issue_list=""
        for issue in "${layer_issue_array[@]}"; do
            issue_list="$issue_list #$issue"
        done
        log_info ""
        log_info "=== Layer $current_layer:${issue_list} ==="
    fi

    # 実行
    if [[ "$sequential" == "true" ]] || [[ ${#layer_issue_array[@]} -eq 1 ]]; then
        if ! execute_layer_sequential _failed_issues_ref _completed_issues_ref _config_ref "${layer_issue_array[@]}"; then
            return 1
        fi
    else
        if ! execute_layer_parallel _failed_issues_ref _completed_issues_ref _config_ref "${layer_issue_array[@]}"; then
            return 1
        fi
    fi

    if [[ "$quiet" != "true" ]]; then
        log_info "✓ Layer $current_layer completed"
    fi

    return 0
}

# 結果サマリーを表示して終了
# 引数:
#   $1: all_issues への参照（配列）
#   $2: failed_issues への参照（配列）
# 戻り値: 0=全成功, 1=一部失敗（exitで終了）
show_summary_and_exit() {
    local -n _all_issues_ref="$1"
    # shellcheck disable=SC2178  # nameref to array is intentional
    local -n _failed_issues_ref="$2"

    echo ""
    if [[ ${#_failed_issues_ref[@]} -gt 0 ]]; then
        log_error "${#_failed_issues_ref[@]} issue(s) failed: ${_failed_issues_ref[*]}"
        echo ""
        echo "Failed issues:"
        for issue in "${_failed_issues_ref[@]}"; do
            echo "  - #$issue"
        done
        exit 1
    else
        log_info "✅ All ${#_all_issues_ref[@]} issues completed successfully"
        exit 0
    fi
}
