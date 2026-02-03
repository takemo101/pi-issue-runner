#!/usr/bin/env bash
# run-batch.sh - 複数Issueを依存関係順に自動実行
#
# このスクリプトはバッチ処理のオーケストレーションを行い、
# コア機能は lib/batch.sh に委譲しています。
#
# shellcheck disable=SC2034
# 上記: グローバル変数は lib/batch.sh で使用される

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

# グローバル設定（lib/batch.sh と共有）- sourceの前に定義
DRY_RUN=false
# shellcheck disable=SC2034
SEQUENTIAL=false
# shellcheck disable=SC2034
CONTINUE_ON_ERROR=false
# shellcheck disable=SC2034
TIMEOUT=3600
# shellcheck disable=SC2034
INTERVAL=5
# shellcheck disable=SC2034
WORKFLOW_NAME="default"
# shellcheck disable=SC2034
BASE_BRANCH="HEAD"
QUIET=false

# ライブラリ読み込み
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/github.sh"
source "$SCRIPT_DIR/../lib/dependency.sh"
source "$SCRIPT_DIR/../lib/status.sh"
source "$SCRIPT_DIR/../lib/batch.sh"    # バッチ処理コア機能

# 設定ファイルの存在チェック（必須）
require_config_file "pi-run-batch" || exit 1

# 統計情報（lib/batch.sh と共有）
# shellcheck disable=SC2034
ALL_ISSUES=()
# shellcheck disable=SC2034
FAILED_ISSUES=()
# shellcheck disable=SC2034
COMPLETED_ISSUES=()

# 引数パース用の一時変数
# 注: parse_arguments 内でローカル使用し、グローバル変数に反映する
declare -a PARSE_ISSUES=()
declare PARSE_PARENT=""

# 引数をパースしてグローバル変数に格納
# グローバル変数を設定: PARSE_ISSUES, PARSE_PARENT, DRY_RUN, SEQUENTIAL等
# 戻り値: 0=成功, 1=エラー (usageを表示して終了)
parse_arguments() {
    # リセット
    PARSE_ISSUES=()
    PARSE_PARENT=""

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
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--timeout requires a value"
                    return 1
                fi
                TIMEOUT="$2"
                shift 2
                ;;
            --interval)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--interval requires a value"
                    return 1
                fi
                INTERVAL="$2"
                shift 2
                ;;
            --parent)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--parent requires a value"
                    return 1
                fi
                PARSE_PARENT="$2"
                shift 2
                ;;
            --workflow)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--workflow requires a value"
                    return 1
                fi
                WORKFLOW_NAME="$2"
                shift 2
                ;;
            --base)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--base requires a value"
                    return 1
                fi
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
                return 1
                ;;
            *)
                # 数字チェック
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    PARSE_ISSUES+=("$1")
                else
                    log_error "Invalid issue number: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    return 0
}

main() {
    # 引数パース（グローバル変数 PARSE_ISSUES, PARSE_PARENT に設定）
    if ! parse_arguments "$@"; then
        usage >&2
        exit 3
    fi

    # 設定読み込み
    load_config

    # 親Issueが指定された場合、Subtaskを展開（将来拡張）
    if [[ -n "$PARSE_PARENT" ]]; then
        log_warn "--parent option is not yet implemented, ignoring"
    fi

    # Issue番号が指定されているかチェック
    if [[ ${#PARSE_ISSUES[@]} -eq 0 ]]; then
        log_error "At least one issue number is required"
        usage >&2
        exit 3
    fi

    ALL_ISSUES=("${PARSE_ISSUES[@]}")

    if [[ "$QUIET" != "true" ]]; then
        log_info "Analyzing dependencies for ${#PARSE_ISSUES[@]} issues..."
    fi

    # 循環依存チェック
    if ! detect_cycles "${PARSE_ISSUES[@]}"; then
        log_error "Circular dependency detected"
        exit 2
    fi

    # レイヤー計算
    local layers_output
    layers_output="$(compute_layers "${PARSE_ISSUES[@]}")"

    # 実行計画表示
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Execution plan:"
        echo "$layers_output" | group_layers | while IFS= read -r line; do
            log_info "  $line"
        done
        log_info "No changes made (dry run)"
        exit 0
    fi

    # 実行計画を表示（lib/batch.sh の関数を使用）
    show_execution_plan "${PARSE_ISSUES[@]}"

    # 最大レイヤー番号を取得
    local max_layer
    max_layer="$(get_max_layer <<< "$layers_output")"

    # レイヤーごとに実行
    local current_layer=0

    while [[ $current_layer -le $max_layer ]]; do
        local result
        process_layer "$current_layer" "$layers_output"
        result=$?

        if [[ $result -eq 1 ]]; then
            # エラー発生
            exit 1
        elif [[ $result -eq 2 ]]; then
            # 空レイヤー - スキップ
            :  # 何もしない
        fi

        ((current_layer++))
    done

    # 結果サマリー（lib/batch.sh の関数を使用）
    show_summary_and_exit
}

main "$@"
