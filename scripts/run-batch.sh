#!/usr/bin/env bash
# run-batch.sh - 複数Issueを依存関係順に自動実行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ヘルプ表示
usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number>... [options]

Arguments:
    issue-number...   実行するIssue番号（複数指定可）

Options:
    --dry-run           実行計画のみ表示（実行しない）
    --sequential        並列実行せず順次実行
    --continue-on-error エラーがあっても次のレイヤーを実行
    --timeout <sec>     完了待機のタイムアウト（デフォルト: 3600）
    --interval <sec>    完了確認の間隔（デフォルト: 5）
    --parent <issue>    親IssueのSubtaskを自動展開（将来拡張）
    --workflow <name>   使用するワークフロー名（デフォルト: default）
    --base <branch>     ベースブランチ（デフォルト: HEAD）
    -q, --quiet         進捗表示を抑制
    -v, --verbose       詳細ログを出力
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") 482 483 484 485 486
    $(basename "$0") 482 483 --dry-run
    $(basename "$0") 482 483 --sequential
    $(basename "$0") 482 483 --continue-on-error

Exit codes:
    0 - 全Issue成功
    1 - 一部Issueが失敗
    2 - 循環依存を検出
    3 - 引数エラー
EOF
}

# ライブラリ読み込み
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/dependency.sh"
source "$SCRIPT_DIR/../lib/status.sh"

# グローバル設定
DRY_RUN=false
SEQUENTIAL=false
CONTINUE_ON_ERROR=false
TIMEOUT=3600
INTERVAL=5
WORKFLOW_NAME="default"
BASE_BRANCH="HEAD"
QUIET=false

# 統計情報
declare -a ALL_ISSUES=()
declare -a FAILED_ISSUES=()
declare -a COMPLETED_ISSUES=()

main() {
    local -a issues=()
    local parent_issue=""

    # 引数パース
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --sequential)
                SEQUENTIAL=true
                shift
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --interval)
                INTERVAL="$2"
                shift 2
                ;;
            --parent)
                parent_issue="$2"
                shift 2
                ;;
            --workflow)
                WORKFLOW_NAME="$2"
                shift 2
                ;;
            --base)
                BASE_BRANCH="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
                enable_quiet
                shift
                ;;
            -v|--verbose)
                enable_verbose
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
                # 数字チェック
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

    # 設定読み込み
    load_config

    # 親Issueが指定された場合、Subtaskを展開（将来拡張）
    if [[ -n "$parent_issue" ]]; then
        log_warn "--parent option is not yet implemented, ignoring"
    fi

    # Issue番号が指定されているかチェック
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_error "At least one issue number is required"
        usage >&2
        exit 3
    fi

    ALL_ISSUES=("${issues[@]}")

    if [[ "$QUIET" != "true" ]]; then
        log_info "Analyzing dependencies for ${#issues[@]} issues..."
    fi

    # 循環依存チェック
    if ! detect_cycles "${issues[@]}"; then
        log_error "Circular dependency detected"
        exit 2
    fi

    # レイヤー計算
    local layers_output
    layers_output="$(compute_layers "${issues[@]}")"

    # 実行計画表示
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Execution plan:"
        echo "$layers_output" | group_layers | while IFS= read -r line; do
            log_info "  $line"
        done
        log_info "No changes made (dry run)"
        exit 0
    fi

    # 実行計画を表示
    show_execution_plan "${issues[@]}"

    # 最大レイヤー番号を取得
    local max_layer
    max_layer="$(echo "$layers_output" | get_max_layer)"

    # レイヤーごとに実行
    local current_layer=0
    local has_error=false

    while [[ $current_layer -le $max_layer ]]; do
        # 現在のレイヤーのIssueを取得
        local layer_issues
        layer_issues="$(get_issues_in_layer "$current_layer" "$layers_output")"

        if [[ -z "$layer_issues" ]]; then
            ((current_layer++))
            continue
        fi

        # レイヤー内のIssueを配列に変換
        local -a layer_issue_array=()
        while IFS= read -r issue; do
            [[ -n "$issue" ]] && layer_issue_array+=("$issue")
        done <<< "$layer_issues"

        if [[ ${#layer_issue_array[@]} -eq 0 ]]; then
            ((current_layer++))
            continue
        fi

        # レイヤー開始
        if [[ "$QUIET" != "true" ]]; then
            local issue_list=""
            for issue in "${layer_issue_array[@]}"; do
                issue_list="$issue_list #$issue"
            done
            log_info ""
            log_info "=== Layer $current_layer:${issue_list} ==="
        fi

        # 実行
        if [[ "$SEQUENTIAL" == "true" ]] || [[ ${#layer_issue_array[@]} -eq 1 ]]; then
            # 順次実行
            for issue in "${layer_issue_array[@]}"; do
                if ! execute_issue "$issue"; then
                    FAILED_ISSUES+=("$issue")
                    has_error=true
                    if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
                        log_error "Issue #$issue failed, aborting"
                        exit 1
                    fi
                else
                    COMPLETED_ISSUES+=("$issue")
                fi
            done
        else
            # 並列実行
            for issue in "${layer_issue_array[@]}"; do
                if [[ "$QUIET" != "true" ]]; then
                    log_info "Starting pi-issue-$issue..."
                fi
                execute_issue_async "$issue"
            done

            # 完了待機
            if [[ "$QUIET" != "true" ]]; then
                log_info "Waiting for completion..."
            fi

            if ! wait_for_layer_completion "${layer_issue_array[@]}"; then
                # shellcheck disable=SC2034
                has_error=true
                if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
                    log_error "Layer $current_layer failed, aborting"
                    exit 1
                fi
            fi
        fi

        if [[ "$QUIET" != "true" ]]; then
            log_info "✓ Layer $current_layer completed"
        fi

        ((current_layer++))
    done

    # 結果サマリー
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

# Issueを実行（同期的）
# 引数: issue_number
# 戻り値: 0=成功, 1=失敗
execute_issue() {
    local issue_number="$1"

    if [[ "$QUIET" != "true" ]]; then
        log_info "Starting pi-issue-$issue_number..."
    fi

    local run_script
    run_script="$SCRIPT_DIR/run.sh"

    if [[ "$QUIET" != "true" ]]; then
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
    run_script="$SCRIPT_DIR/run.sh"

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

        if [[ $elapsed -ge $TIMEOUT ]]; then
            log_error "Timeout after ${elapsed}s"
            return 1
        fi

        sleep "$INTERVAL"
    done
}

main "$@"
