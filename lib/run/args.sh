#!/usr/bin/env bash
# ============================================================================
# run/args.sh - Command-line argument parsing for run.sh
#
# Handles parsing of all command-line options and provides usage information.
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_RUN_ARGS_SH_SOURCED:-}" ]]; then
    return 0
fi
_RUN_ARGS_SH_SOURCED="true"

# ライブラリディレクトリを取得
_RUN_ARGS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存関係の読み込み
source "$_RUN_ARGS_LIB_DIR/../config.sh"
source "$_RUN_ARGS_LIB_DIR/../log.sh"
source "$_RUN_ARGS_LIB_DIR/../workflow.sh"

# ============================================================================
# Show usage information
# ============================================================================
usage() {
    cat << EOF
Usage: $(basename "$0") <issue-number> [options]

Arguments:
    issue-number    GitHub Issue番号

Options:
    -i, --issue NUMBER  Issue番号（位置引数の代替）
    -b, --branch NAME   カスタムブランチ名（デフォルト: issue-<num>-<title>）
    --base BRANCH       ベースブランチ（デフォルト: HEAD）
    -w, --workflow NAME ワークフロー名（デフォルト: default）
                        ビルトイン: default, simple, thorough, ci-fix, auto
    -l, --label LABEL   セッションラベル（識別用タグ）
    --no-attach         セッション作成後にアタッチしない
    --no-cleanup        エージェント終了後の自動クリーンアップを無効化
    --no-gates          ゲート（品質チェック）を無効化（非推奨: --skip-run を使用）
    --skip-run          run: ステップをスキップ
    --skip-call         エージェント呼び出しをスキップ（テスト用）
    --reattach          既存セッションがあればアタッチ
    --force             既存セッション/worktreeを削除して再作成
    --agent-args ARGS   エージェントに渡す追加の引数
    --pi-args ARGS      --agent-args のエイリアス（後方互換性）
    --list-workflows    利用可能なワークフロー一覧を表示
    --ignore-blockers   依存関係チェックをスキップして強制実行
    --show-config       現在の設定を表示（デバッグ用）
    --list-agents       利用可能なエージェントプリセット一覧を表示
    --show-agent-config エージェント設定を表示（デバッグ用）
    -v, --verbose       詳細ログを表示
    --quiet             エラーのみ表示
    -h, --help          このヘルプを表示

Examples:
    $(basename "$0") 42
    $(basename "$0") --issue 42
    $(basename "$0") 42 -w simple
    $(basename "$0") 42 --no-attach
    $(basename "$0") 42 --no-cleanup
    $(basename "$0") 42 --reattach
    $(basename "$0") 42 --force
    $(basename "$0") 42 -b custom-feature
    $(basename "$0") 42 --base develop
EOF
}

# ============================================================================
# Parse command-line arguments
# Output: Sets global variables with _PARSE_ prefix
# ============================================================================
parse_run_arguments() {
    local issue_number=""
    local custom_branch=""
    local base_branch=""
    local workflow_name=""
    local workflow_specified=false
    local no_attach=false
    local reattach=false
    local force=false
    local extra_agent_args=""
    local cleanup_mode="auto"
    local list_workflows=false
    local ignore_blockers=false
    local session_label=""
    local no_gates=false
    local skip_call=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue|-i)
                issue_number="$2"
                shift 2
                ;;
            --branch|-b)
                custom_branch="$2"
                shift 2
                ;;
            --base)
                base_branch="$2"
                shift 2
                ;;
            --workflow|-w)
                workflow_name="$2"
                workflow_specified=true
                shift 2
                ;;
            --label|-l)
                session_label="$2"
                shift 2
                ;;
            --list-workflows)
                list_workflows=true
                shift
                ;;
            --no-attach)
                no_attach=true
                shift
                ;;
            --reattach)
                reattach=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --no-cleanup)
                cleanup_mode="none"
                shift
                ;;
            --no-gates|--skip-run)
                no_gates=true
                shift
                ;;
            --skip-call)
                skip_call=true
                shift
                ;;
            --ignore-blockers)
                ignore_blockers=true
                shift
                ;;
            -v|--verbose)
                enable_verbose
                shift
                ;;
            --quiet)
                enable_quiet
                shift
                ;;
            --agent-args|--pi-args)
                extra_agent_args="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$issue_number" ]]; then
                    issue_number="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Set global variables (no escaping needed - direct assignment is safe)
    _PARSE_issue_number="$issue_number"
    _PARSE_custom_branch="$custom_branch"
    _PARSE_base_branch="$base_branch"
    # -w 未指定時はデフォルトワークフローを自動解決
    if [[ "$workflow_specified" == "false" ]]; then
        workflow_name="$(resolve_default_workflow ".")"
    fi
    _PARSE_workflow_name="$workflow_name"
    _PARSE_no_attach="$no_attach"
    _PARSE_reattach="$reattach"
    _PARSE_force="$force"
    _PARSE_extra_agent_args="$extra_agent_args"
    _PARSE_cleanup_mode="$cleanup_mode"
    _PARSE_list_workflows="$list_workflows"
    _PARSE_ignore_blockers="$ignore_blockers"
    _PARSE_session_label="$session_label"
    _PARSE_no_gates="$no_gates"
    _PARSE_skip_call="$skip_call"
}

# ============================================================================
# Validate inputs and load configuration
# Arguments: $1=issue_number, $2=list_workflows
# ============================================================================
validate_run_inputs() {
    local issue_number="$1"
    local list_workflows="$2"

    # --list-workflowsオプションの処理
    if [[ "$list_workflows" == "true" ]]; then
        log_info "Available workflows:"
        list_available_workflows
        exit 0
    fi

    if [[ -z "$issue_number" ]]; then
        log_error "Issue number is required"
        usage >&2
        exit 1
    fi

    # Issue番号が正の整数であることを検証
    if [[ ! "$issue_number" =~ ^[0-9]+$ ]]; then
        log_error "Issue number must be a positive integer: $issue_number"
        exit 1
    fi

    # 設定読み込み
    load_config
}
