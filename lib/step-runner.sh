#!/usr/bin/env bash
# step-runner.sh - run:/call: ステップの実行エンジン
#
# 提供関数:
#   - run_command_step: run: ステップ（外部コマンド）を実行
#   - run_call_step: call: ステップ（別ワークフロー呼び出し）を実行
#   - expand_step_variables: テンプレート変数を展開

set -euo pipefail

# ソースガード
if [[ -n "${_STEP_RUNNER_SH_SOURCED:-}" ]]; then
    return 0
fi
_STEP_RUNNER_SH_SOURCED="true"

_STEP_RUNNER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_STEP_RUNNER_LIB_DIR/compat.sh"
source "$_STEP_RUNNER_LIB_DIR/log.sh"
source "$_STEP_RUNNER_LIB_DIR/marker.sh"
source "$_STEP_RUNNER_LIB_DIR/yaml.sh"
source "$_STEP_RUNNER_LIB_DIR/workflow-loader.sh"

# ===================
# テンプレート変数展開
# ===================

# run: コマンド内のテンプレート変数を展開
# Usage: expand_step_variables <command_string> [issue_number] [pr_number] [branch_name] [worktree_path]
expand_step_variables() {
    local cmd="$1"
    local issue_number="${2:-${PI_ISSUE_NUMBER:-}}"
    local pr_number="${3:-${PI_PR_NUMBER:-}}"
    local branch_name="${4:-${PI_BRANCH_NAME:-}}"
    local worktree_path="${5:-${PI_WORKTREE_PATH:-}}"

    local result="$cmd"
    result="${result//\$\{issue_number\}/$issue_number}"
    result="${result//\$\{pr_number\}/$pr_number}"
    result="${result//\$\{branch_name\}/$branch_name}"
    result="${result//\$\{worktree_path\}/$worktree_path}"
    echo "$result"
}

# ===================
# run: ステップ実行
# ===================

# 外部コマンドを worktree 内で実行
# Usage: run_command_step <command> <timeout> <worktree_path> [issue_number] [pr_number] [branch_name]
# Returns: 0=成功, 1=失敗, 124=タイムアウト
# Output: コマンドの stdout/stderr を stdout に出力
run_command_step() {
    local command="$1"
    local timeout="${2:-900}"
    local worktree_path="${3:-.}"
    local issue_number="${4:-${PI_ISSUE_NUMBER:-}}"
    local pr_number="${5:-${PI_PR_NUMBER:-}}"
    local branch_name="${6:-${PI_BRANCH_NAME:-}}"

    # テンプレート変数を展開
    local expanded_cmd
    expanded_cmd=$(expand_step_variables "$command" "$issue_number" "$pr_number" "$branch_name" "$worktree_path")

    log_info "run: $expanded_cmd (timeout: ${timeout}s)"

    # worktree 内で実行
    local output=""
    local exit_code=0
    output=$(
        cd "$worktree_path" 2>/dev/null || true
        safe_timeout "$timeout" env \
            PI_ISSUE_NUMBER="$issue_number" \
            PI_PR_NUMBER="$pr_number" \
            PI_BRANCH_NAME="$branch_name" \
            PI_WORKTREE_PATH="$worktree_path" \
            bash -c "$expanded_cmd" 2>&1
    ) || exit_code=$?

    # 出力を表示
    if [[ -n "$output" ]]; then
        echo "$output"
    fi

    if [[ $exit_code -eq 124 ]]; then
        log_warn "run: timed out after ${timeout}s: $command"
    elif [[ $exit_code -ne 0 ]]; then
        log_warn "run: failed (exit $exit_code): $command"
    else
        log_info "run: passed"
    fi

    return $exit_code
}

# ===================
# call: ステップ実行
# ===================

# 別ワークフローを別AIインスタンスで実行
# Usage: run_call_step <workflow_name> <timeout> <worktree_path> [config_file] [issue_number] [branch_name]
# Returns: 0=成功(COMPLETEマーカー検出), 1=失敗
# Output: AIの出力を stdout に出力
run_call_step() {
    local workflow_name="$1"
    local timeout="${2:-900}"
    local worktree_path="${3:-.}"
    local config_file="${4:-${PI_RUNNER_CONFIG_FILE:-}}"
    local issue_number="${5:-${PI_ISSUE_NUMBER:-0}}"
    local branch_name="${6:-${PI_BRANCH_NAME:-}}"

    # 設定ファイル解決
    if [[ -z "$config_file" ]] && [[ -f "$worktree_path/.pi-runner.yaml" ]]; then
        config_file="$worktree_path/.pi-runner.yaml"
    fi

    # ワークフロー存在確認
    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
        if ! yaml_exists "$config_file" ".workflows.${workflow_name}"; then
            log_error "Workflow not found: $workflow_name"
            echo "Workflow not found: $workflow_name"
            return 1
        fi
    else
        log_error "Config file not found, cannot resolve call: $workflow_name"
        echo "Config file not found, cannot resolve call: $workflow_name"
        return 1
    fi

    # プロンプトファイルを生成（write_workflow_prompt で agents/*.md テンプレートを使用）
    local prompt_file
    prompt_file="$(mktemp "${TMPDIR:-/tmp}/pi-call-step-XXXXXX.md")"

    # Issue タイトルを取得（利用可能な場合）
    local issue_title=""
    issue_title=$(cd "$worktree_path" && gh issue view "$issue_number" --json title -q '.title' 2>/dev/null) || issue_title=""

    write_workflow_prompt "$prompt_file" "$workflow_name" "$issue_number" "$issue_title" "" \
        "$branch_name" "$worktree_path" "$worktree_path" ""

    # エージェント設定を取得
    local agent_type agent_args=""
    agent_type=$(yaml_get "$config_file" ".workflows.${workflow_name}.agent.type" 2>/dev/null || echo "")
    while IFS= read -r arg; do
        [[ -n "$arg" ]] && agent_args="${agent_args:+$agent_args }$arg"
    done < <(yaml_get_array "$config_file" ".workflows.${workflow_name}.agent.args" 2>/dev/null)

    # フォールバック: グローバルagent設定
    if [[ -z "$agent_type" ]]; then
        agent_type=$(yaml_get "$config_file" ".agent.type" 2>/dev/null || echo "pi")
    fi
    if [[ -z "$agent_args" ]]; then
        while IFS= read -r arg; do
            [[ -n "$arg" ]] && agent_args="${agent_args:+$agent_args }$arg"
        done < <(yaml_get_array "$config_file" ".agent.args" 2>/dev/null)
    fi

    # コマンド組み立て
    # call: ステップは非インタラクティブで実行する必要がある（処理完了後に自動終了）
    local agent_command agent_template
    case "$agent_type" in
        pi)       agent_command="pi";       agent_template='{{command}} --print {{args}} @"{{prompt_file}}"' ;;
        claude)   agent_command="claude";   agent_template='{{command}} {{args}} --print "{{prompt_file}}"' ;;
        opencode) agent_command="opencode"; agent_template='cat "{{prompt_file}}" | {{command}} {{args}}' ;;
        *)        agent_command="$agent_type"; agent_template='{{command}} --print {{args}} @"{{prompt_file}}"' ;;
    esac

    local full_command="$agent_template"
    full_command="${full_command//\{\{command\}\}/$agent_command}"
    full_command="${full_command//\{\{args\}\}/$agent_args}"
    full_command="${full_command//\{\{prompt_file\}\}/$prompt_file}"

    log_info "call: $workflow_name (agent: $agent_type, timeout: ${timeout}s)"

    # 実行
    local output="" exit_code=0
    output=$(
        cd "$worktree_path" 2>/dev/null || true
        safe_timeout "$timeout" bash -c "$full_command" 2>&1
    ) || exit_code=$?

    rm -f "$prompt_file"

    if [[ -n "$output" ]]; then
        echo "$output"
    fi

    # タイムアウト
    if [[ $exit_code -eq 124 ]]; then
        log_warn "call: timed out after ${timeout}s: $workflow_name"
        return 1
    fi

    # マーカー判定
    local complete_marker="###TASK_COMPLETE_${issue_number}###"
    local error_marker="###TASK_ERROR_${issue_number}###"

    if [[ $(count_markers_outside_codeblock "$output" "$complete_marker") -gt 0 ]]; then
        log_info "call: passed ($workflow_name)"
        return 0
    fi

    if [[ $(count_markers_outside_codeblock "$output" "$error_marker") -gt 0 ]]; then
        log_error "call: failed ($workflow_name) — ERROR marker detected"
        return 1
    fi

    # マーカーなし: 終了コードで判定
    if [[ $exit_code -ne 0 ]]; then
        log_error "call: failed ($workflow_name) — exit code $exit_code"
        return 1
    fi

    # 正常終了、マーカーなし → 通過扱い
    log_info "call: passed ($workflow_name) — no marker, exit 0"
    return 0
}
