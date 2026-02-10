#!/usr/bin/env bash
# gates.sh - ゲート実行エンジン（品質ゲート機能の基盤）
#
# COMPLETEマーカー検出後に外部コマンドで品質検証を行う仕組み。
# 仕様書: docs/gates-spec.md
#
# Provides:
#   - parse_gate_config: YAML設定からゲートリストをパース
#   - expand_gate_variables: テンプレート変数を展開
#   - run_single_gate: 単一ゲートの実行
#   - run_call_gate: call形式ゲートの実行（別ワークフローをAIで実行）
#   - run_gates: ゲートリストを順番に実行
#   - detect_call_cycle: call: の循環呼び出し検出

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_GATES_SH_SOURCED:-}" ]]; then
    return 0
fi
_GATES_SH_SOURCED="true"

_GATES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリ読み込み
source "$_GATES_LIB_DIR/log.sh"
source "$_GATES_LIB_DIR/yaml.sh"
source "$_GATES_LIB_DIR/compat.sh"
source "$_GATES_LIB_DIR/marker.sh"

# ===================
# 定数
# ===================

# デフォルトタイムアウト（秒）
GATE_DEFAULT_TIMEOUT="${GATE_DEFAULT_TIMEOUT:-300}"

# デフォルトリトライ設定
GATE_DEFAULT_MAX_RETRY="${GATE_DEFAULT_MAX_RETRY:-0}"
GATE_DEFAULT_RETRY_INTERVAL="${GATE_DEFAULT_RETRY_INTERVAL:-10}"

# ===================
# parse_gate_config - YAML設定からゲートリストをパース
# ===================

# YAML設定からゲートリストをパース
# 3形式を解析: シンプル（文字列）、詳細（command）、call形式
#
# Usage: parse_gate_config <config_file> [workflow_name]
# - workflow_name指定時: .workflows.<name>.gates を参照
# - workflow_name未指定: トップレベル .gates を参照
#
# 出力: 1行1ゲート。タブ区切りフィールド:
#   type\tcommand_or_name\ttimeout\tmax_retry\tretry_interval\tcontinue_on_fail\tdescription
#   type: "simple", "command", "call"
parse_gate_config() {
    local config_file="$1"
    local workflow_name="${2:-}"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    local gates_path
    if [[ -n "$workflow_name" ]]; then
        gates_path=".workflows.${workflow_name}.gates"
    else
        gates_path=".gates"
    fi

    # ゲートセクションが存在しない場合は空で返す
    if ! yaml_exists "$config_file" "$gates_path"; then
        return 0
    fi

    # yq が使える場合は yq で詳細パース
    if check_yq; then
        _parse_gates_with_yq "$config_file" "$gates_path"
    else
        _parse_gates_simple "$config_file" "$gates_path"
    fi
}

# yq を使ったゲートパース
_parse_gates_with_yq() {
    local config_file="$1"
    local gates_path="$2"

    _yaml_ensure_cached "$config_file"

    local count
    count=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${gates_path} | length" - 2>/dev/null) || count=0

    if [[ "$count" -eq 0 ]]; then
        return 0
    fi

    local i
    for (( i = 0; i < count; i++ )); do
        local item_path="${gates_path}[$i]"
        local item_type

        # アイテムの型を判定
        item_type=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path} | type" - 2>/dev/null) || item_type="!!str"

        if [[ "$item_type" == "!!str" ]]; then
            # シンプル形式: 文字列
            local cmd
            cmd=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}" - 2>/dev/null) || cmd=""
            if [[ -n "$cmd" ]]; then
                printf "simple\t%s\t%s\t%s\t%s\tfalse\t\n" \
                    "$cmd" "$GATE_DEFAULT_TIMEOUT" "$GATE_DEFAULT_MAX_RETRY" "$GATE_DEFAULT_RETRY_INTERVAL"
            fi
        elif [[ "$item_type" == "!!map" ]]; then
            # マップ形式: command または call
            local cmd call_name timeout max_retry retry_interval continue_on_fail description
            cmd=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.command // \"\"" - 2>/dev/null) || cmd=""
            call_name=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.call // \"\"" - 2>/dev/null) || call_name=""
            timeout=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.timeout // \"${GATE_DEFAULT_TIMEOUT}\"" - 2>/dev/null) || timeout="$GATE_DEFAULT_TIMEOUT"
            max_retry=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.max_retry // \"${GATE_DEFAULT_MAX_RETRY}\"" - 2>/dev/null) || max_retry="$GATE_DEFAULT_MAX_RETRY"
            retry_interval=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.retry_interval // \"${GATE_DEFAULT_RETRY_INTERVAL}\"" - 2>/dev/null) || retry_interval="$GATE_DEFAULT_RETRY_INTERVAL"
            continue_on_fail=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.continue_on_fail // \"false\"" - 2>/dev/null) || continue_on_fail="false"
            description=$(echo "$_YAML_CACHE_CONTENT" | yq -r "${item_path}.description // \"\"" - 2>/dev/null) || description=""

            if [[ -n "$cmd" ]]; then
                printf "command\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                    "$cmd" "$timeout" "$max_retry" "$retry_interval" "$continue_on_fail" "$description"
            elif [[ -n "$call_name" ]]; then
                printf "call\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                    "$call_name" "$timeout" "$max_retry" "$retry_interval" "$continue_on_fail" "$description"
            fi
        fi
    done
}

# 簡易パーサーによるゲートパース（yq なし）
# シンプル形式のみサポート
_parse_gates_simple() {
    local config_file="$1"
    local gates_path="$2"

    # yaml_get_array でシンプル形式の文字列を取得
    while IFS= read -r item; do
        if [[ -n "$item" ]]; then
            printf "simple\t%s\t%s\t%s\t%s\tfalse\t\n" \
                "$item" "$GATE_DEFAULT_TIMEOUT" "$GATE_DEFAULT_MAX_RETRY" "$GATE_DEFAULT_RETRY_INTERVAL"
        fi
    done < <(yaml_get_array "$config_file" "$gates_path")
}

# ===================
# expand_gate_variables - テンプレート変数を展開
# ===================

# ゲートコマンド内のテンプレート変数を展開
# 変数形式: ${variable_name}
#
# 対応変数:
#   ${issue_number} - Issue番号
#   ${pr_number} - PR番号
#   ${branch_name} - ブランチ名
#   ${worktree_path} - worktreeのパス
#
# 環境変数からも取得:
#   PI_ISSUE_NUMBER, PI_PR_NUMBER, PI_BRANCH_NAME, PI_WORKTREE_PATH
#
# Usage: expand_gate_variables <command_string> [issue_number] [pr_number] [branch_name] [worktree_path]
expand_gate_variables() {
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
# run_single_gate - 単一ゲートの実行
# ===================

# 単一ゲートを実行
# コマンドを実行し、stdout/stderrをキャプチャ
#
# Usage: run_single_gate <command> [timeout] [cwd]
# Returns: 0=通過, 1=失敗（タイムアウト含む）
# Output: コマンドの出力（stdout+stderr）をstdoutに出力
run_single_gate() {
    local command="$1"
    local timeout="${2:-$GATE_DEFAULT_TIMEOUT}"
    local cwd="${3:-${PI_WORKTREE_PATH:-.}}"

    local output
    local exit_code=0

    # コマンドを worktree ディレクトリで実行
    # stdout と stderr を両方キャプチャ
    output=$(
        cd "$cwd" 2>/dev/null || true
        safe_timeout "$timeout" env \
            PI_ISSUE_NUMBER="${PI_ISSUE_NUMBER:-}" \
            PI_BRANCH_NAME="${PI_BRANCH_NAME:-}" \
            PI_WORKTREE_PATH="${PI_WORKTREE_PATH:-$cwd}" \
            bash -c "$command" 2>&1
    ) || exit_code=$?

    # 出力を表示
    if [[ -n "$output" ]]; then
        echo "$output"
    fi

    # タイムアウト（exit code 124）も失敗扱い
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            log_warn "Gate timed out after ${timeout}s: $command"
        fi
        return 1
    fi

    return 0
}

# ===================
# run_call_gate - call形式ゲートの実行
# ===================

# call形式ゲートを実行
# 別ワークフローを別AIインスタンスとして実行し、結果を判定する
#
# Usage: run_call_gate <workflow_name> <timeout> <worktree_path> [config_file] [issue_number] [branch_name] [calling_workflow]
# Returns: 0=通過（COMPLETEマーカー検出）, 1=失敗（ERROR/タイムアウト/循環）
# Output: AIの出力をstdoutに出力
run_call_gate() {
    local workflow_name="$1"
    local timeout="${2:-$GATE_DEFAULT_TIMEOUT}"
    local worktree_path="${3:-.}"
    local config_file="${4:-}"
    local issue_number="${5:-${PI_ISSUE_NUMBER:-0}}"
    local branch_name="${6:-${PI_BRANCH_NAME:-}}"
    local calling_workflow="${7:-}"

    # 設定ファイルの解決
    if [[ -z "$config_file" ]]; then
        config_file="${PI_RUNNER_CONFIG_FILE:-}"
        if [[ -z "$config_file" ]] && [[ -f "$worktree_path/.pi-runner.yaml" ]]; then
            config_file="$worktree_path/.pi-runner.yaml"
        fi
    fi

    # 循環呼び出し検出
    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
        local cycle_chain="${calling_workflow:-}"
        if ! detect_call_cycle "$config_file" "$workflow_name" "$cycle_chain"; then
            echo "Call cycle detected for workflow: $workflow_name"
            return 1
        fi
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

    # git diff を取得してプロンプトに含めるための準備
    local diff_content=""
    if [[ -d "$worktree_path/.git" ]] || [[ -f "$worktree_path/.git" ]]; then
        diff_content=$(cd "$worktree_path" && git diff origin/main 2>/dev/null || git diff HEAD 2>/dev/null || echo "")
    fi

    # プロンプトファイルを生成
    local prompt_file
    prompt_file="$(mktemp "${TMPDIR:-/tmp}/pi-call-gate-XXXXXX.md")"

    # ワークフローのステップを取得してプロンプトを構築
    local steps=""
    while IFS= read -r step; do
        [[ -n "$step" ]] && steps="${steps:+$steps }$step"
    done < <(yaml_get_array "$config_file" ".workflows.${workflow_name}.steps")

    local description=""
    description=$(yaml_get "$config_file" ".workflows.${workflow_name}.description" 2>/dev/null || echo "")

    # レビュー用プロンプトを構築
    {
        printf '# Gate Review: %s\n\n' "$workflow_name"
        printf 'Workflow: %s\n' "$workflow_name"
        if [[ -n "$description" ]]; then
            printf 'Description: %s\n' "$description"
        fi
        printf 'Steps: %s\n\n' "$steps"
        printf 'Issue: #%s\n' "$issue_number"
        printf 'Branch: %s\n' "$branch_name"
        printf 'Worktree: %s\n\n' "$worktree_path"

        if [[ -n "$diff_content" ]]; then
            printf '## Changes to Review\n\n'
            printf '```diff\n%s\n```\n\n' "$diff_content"
        fi

        printf '## Instructions\n\n'
        printf 'Review the changes above. If everything looks good, output the completion marker.\n'
        printf 'If there are issues, output the error marker with details.\n\n'
        printf 'Completion marker (output on a single line): ###TASK_COMPLETE_%s###\n' "$issue_number"
        printf 'Error marker (output on a single line): ###TASK_ERROR_%s###\n' "$issue_number"
    } > "$prompt_file"

    # エージェント設定を取得・適用
    # ワークフロー固有のagent設定を読み取る
    local agent_type="" agent_command="" agent_args="" agent_template=""
    agent_type=$(yaml_get "$config_file" ".workflows.${workflow_name}.agent.type" 2>/dev/null || echo "")
    agent_command=$(yaml_get "$config_file" ".workflows.${workflow_name}.agent.command" 2>/dev/null || echo "")
    agent_template=$(yaml_get "$config_file" ".workflows.${workflow_name}.agent.template" 2>/dev/null || echo "")

    # args は配列
    while IFS= read -r arg; do
        [[ -n "$arg" ]] && agent_args="${agent_args:+$agent_args }$arg"
    done < <(yaml_get_array "$config_file" ".workflows.${workflow_name}.agent.args" 2>/dev/null)

    # ワークフロー固有の設定が未設定の場合はグローバル設定にフォールバック
    if [[ -z "$agent_type" ]]; then
        agent_type=$(yaml_get "$config_file" ".agent.type" 2>/dev/null || echo "")
        if [[ -z "$agent_type" ]]; then
            agent_type="pi"
        fi
    fi
    if [[ -z "$agent_command" ]]; then
        agent_command=$(yaml_get "$config_file" ".agent.command" 2>/dev/null || echo "")
    fi
    if [[ -z "$agent_template" ]]; then
        agent_template=$(yaml_get "$config_file" ".agent.template" 2>/dev/null || echo "")
    fi
    if [[ -z "$agent_args" ]]; then
        while IFS= read -r arg; do
            [[ -n "$arg" ]] && agent_args="${agent_args:+$agent_args }$arg"
        done < <(yaml_get_array "$config_file" ".agent.args" 2>/dev/null)
    fi

    # プリセットからコマンド・テンプレートを解決
    if [[ -z "$agent_command" ]]; then
        case "$agent_type" in
            pi)      agent_command="pi" ;;
            claude)  agent_command="claude" ;;
            opencode) agent_command="opencode" ;;
            *)       agent_command="$agent_type" ;;
        esac
    fi

    if [[ -z "$agent_template" ]]; then
        case "$agent_type" in
            pi)      agent_template='{{command}} {{args}} @"{{prompt_file}}"' ;;
            claude)  agent_template='{{command}} {{args}} --print "{{prompt_file}}"' ;;
            opencode) agent_template='cat "{{prompt_file}}" | {{command}} {{args}}' ;;
            *)       agent_template='{{command}} {{args}} @"{{prompt_file}}"' ;;
        esac
    fi

    # テンプレート変数を置換
    local full_command="$agent_template"
    full_command="${full_command//\{\{command\}\}/$agent_command}"
    full_command="${full_command//\{\{args\}\}/$agent_args}"
    full_command="${full_command//\{\{prompt_file\}\}/$prompt_file}"

    log_info "Call gate: executing workflow '$workflow_name' with agent '$agent_type'"
    log_debug "Call gate command: $full_command"

    # エージェントを実行してキャプチャ
    local output=""
    local exit_code=0

    output=$(
        cd "$worktree_path" 2>/dev/null || true
        safe_timeout "$timeout" bash -c "$full_command" 2>&1
    ) || exit_code=$?

    # プロンプトファイルのクリーンアップ
    rm -f "$prompt_file"

    # 出力を表示
    if [[ -n "$output" ]]; then
        echo "$output"
    fi

    # タイムアウト判定
    if [[ $exit_code -eq 124 ]]; then
        log_warn "Call gate timed out after ${timeout}s: $workflow_name"
        return 1
    fi

    # マーカー判定
    local complete_marker="###TASK_COMPLETE_${issue_number}###"
    local error_marker="###TASK_ERROR_${issue_number}###"

    # COMPLETEマーカー検出 → 通過
    local complete_count=0
    complete_count=$(count_markers_outside_codeblock "$output" "$complete_marker")
    if [[ $complete_count -gt 0 ]]; then
        log_info "Call gate passed: $workflow_name (COMPLETE marker detected)"
        return 0
    fi

    # ERRORマーカー検出 → 失敗
    local error_count=0
    error_count=$(count_markers_outside_codeblock "$output" "$error_marker")
    if [[ $error_count -gt 0 ]]; then
        log_error "Call gate failed: $workflow_name (ERROR marker detected)"
        return 1
    fi

    # マーカーなし: 終了コードで判定
    if [[ $exit_code -ne 0 ]]; then
        log_error "Call gate failed: $workflow_name (exit code: $exit_code)"
        return 1
    fi

    # 正常終了だがマーカーなし → 通過扱い
    log_info "Call gate passed: $workflow_name (no marker, exit 0)"
    return 0
}

# ===================
# run_gates - ゲートリストを順番に実行
# ===================

# ゲートリストを順番に実行
# parse_gate_config の出力を入力として受け取る
#
# Usage: run_gates <gate_definitions> [issue_number] [pr_number] [branch_name] [worktree_path] [config_file] [calling_workflow]
# gate_definitions: parse_gate_config の出力（タブ区切り形式）
# Returns: 0=全通過, 1=いずれか失敗
# Output: 失敗ゲートの出力をstdoutに出力
run_gates() {
    local gate_definitions="$1"
    local issue_number="${2:-${PI_ISSUE_NUMBER:-}}"
    local pr_number="${3:-${PI_PR_NUMBER:-}}"
    local branch_name="${4:-${PI_BRANCH_NAME:-}}"
    local worktree_path="${5:-${PI_WORKTREE_PATH:-.}}"
    local config_file="${6:-${PI_RUNNER_CONFIG_FILE:-}}"
    local calling_workflow="${7:-}"

    if [[ -z "$gate_definitions" ]]; then
        log_debug "No gates defined, skipping"
        return 0
    fi

    local has_failure=false
    local failed_output=""
    local gate_index=0

    while IFS= read -r gate_line; do
        [[ -z "$gate_line" ]] && continue
        gate_index=$((gate_index + 1))

        local gate_type gate_cmd_or_name gate_timeout gate_max_retry gate_retry_interval gate_continue_on_fail gate_description
        IFS=$'\t' read -r gate_type gate_cmd_or_name gate_timeout gate_max_retry gate_retry_interval gate_continue_on_fail gate_description <<< "$gate_line"

        if [[ "$gate_type" == "call" ]]; then
            local display_name="${gate_description:-call:${gate_cmd_or_name}}"
            log_info "Gate $gate_index: $display_name"

            local attempt=0
            local gate_passed=false

            while [[ $attempt -le ${gate_max_retry:-0} ]]; do
                if [[ $attempt -gt 0 ]]; then
                    log_info "Gate $gate_index: retry $attempt/${gate_max_retry} (waiting ${gate_retry_interval}s)"
                    sleep "${gate_retry_interval:-$GATE_DEFAULT_RETRY_INTERVAL}"
                fi

                local output=""
                local gate_exit=0
                output=$(run_call_gate "$gate_cmd_or_name" "${gate_timeout:-$GATE_DEFAULT_TIMEOUT}" "$worktree_path" "$config_file" "$issue_number" "$branch_name" "$calling_workflow") || gate_exit=$?

                if [[ $gate_exit -eq 0 ]]; then
                    gate_passed=true
                    log_info "Gate $gate_index: PASSED"
                    break
                fi

                attempt=$((attempt + 1))
            done

            if [[ "$gate_passed" == "false" ]]; then
                log_error "Gate $gate_index: FAILED - $display_name"
                if [[ -n "$output" ]]; then
                    failed_output+="Gate failed: ${display_name}"$'\n'"${output}"$'\n'
                else
                    failed_output+="Gate failed: ${display_name}"$'\n'
                fi

                if [[ "$gate_continue_on_fail" == "true" ]]; then
                    log_warn "Gate $gate_index: continue_on_fail=true, continuing..."
                    has_failure=true
                else
                    echo "$failed_output"
                    return 1
                fi
            fi

            continue
        fi

        local expanded_cmd
        expanded_cmd=$(expand_gate_variables "$gate_cmd_or_name" "$issue_number" "$pr_number" "$branch_name" "$worktree_path")

        local display_name="${gate_description:-$expanded_cmd}"
        log_info "Gate $gate_index: $display_name"

        local attempt=0
        local gate_passed=false

        while [[ $attempt -le ${gate_max_retry:-0} ]]; do
            if [[ $attempt -gt 0 ]]; then
                log_info "Gate $gate_index: retry $attempt/${gate_max_retry} (waiting ${gate_retry_interval}s)"
                sleep "${gate_retry_interval:-$GATE_DEFAULT_RETRY_INTERVAL}"
            fi

            local output=""
            local gate_exit=0
            output=$(run_single_gate "$expanded_cmd" "${gate_timeout:-$GATE_DEFAULT_TIMEOUT}" "$worktree_path") || gate_exit=$?

            if [[ $gate_exit -eq 0 ]]; then
                gate_passed=true
                log_info "Gate $gate_index: PASSED"
                break
            fi

            attempt=$((attempt + 1))
        done

        if [[ "$gate_passed" == "false" ]]; then
            log_error "Gate $gate_index: FAILED - $display_name"
            if [[ -n "$output" ]]; then
                failed_output+="Gate failed: ${display_name}"$'\n'"${output}"$'\n'
            else
                failed_output+="Gate failed: ${display_name}"$'\n'
            fi

            if [[ "$gate_continue_on_fail" == "true" ]]; then
                log_warn "Gate $gate_index: continue_on_fail=true, continuing..."
                has_failure=true
            else
                # 失敗出力を表示して即終了
                echo "$failed_output"
                return 1
            fi
        fi
    done <<< "$gate_definitions"

    if [[ "$has_failure" == "true" ]]; then
        echo "$failed_output"
        return 1
    fi

    return 0
}

# ===================
# detect_call_cycle - 循環呼び出し検出
# ===================

# call: の循環呼び出しを検出
# 呼び出しチェーンを構築し、循環を検出する
#
# Usage: detect_call_cycle <config_file> <workflow_name> [visited_chain]
# visited_chain: コロン区切りの訪問済みワークフロー名（内部用）
# Returns: 0=循環なし, 1=循環検出
# Output: 循環検出時はエラーメッセージ
detect_call_cycle() {
    local config_file="$1"
    local workflow_name="$2"
    local visited_chain="${3:-}"

    # 訪問済みチェック
    if [[ -n "$visited_chain" ]]; then
        local name
        local IFS_SAVE="$IFS"
        IFS=":"
        for name in $visited_chain; do
            if [[ "$name" == "$workflow_name" ]]; then
                IFS="$IFS_SAVE"
                log_error "Call cycle detected: ${visited_chain}:${workflow_name}"
                echo "Call cycle detected: ${visited_chain}:${workflow_name}"
                return 1
            fi
        done
        IFS="$IFS_SAVE"
    fi

    # 現在のワークフローを訪問済みに追加
    local new_chain
    if [[ -n "$visited_chain" ]]; then
        new_chain="${visited_chain}:${workflow_name}"
    else
        new_chain="$workflow_name"
    fi

    # このワークフローのゲート設定をパース
    local gates_path=".workflows.${workflow_name}.gates"
    if ! yaml_exists "$config_file" "$gates_path"; then
        return 0
    fi

    # call ゲートを探して再帰的にチェック
    local gate_definitions
    gate_definitions=$(parse_gate_config "$config_file" "$workflow_name")

    if [[ -z "$gate_definitions" ]]; then
        return 0
    fi

    while IFS= read -r gate_line; do
        [[ -z "$gate_line" ]] && continue

        local gate_type gate_cmd_or_name
        IFS=$'\t' read -r gate_type gate_cmd_or_name _ _ _ _ _ <<< "$gate_line"

        if [[ "$gate_type" == "call" ]]; then
            # 再帰的に循環チェック
            if ! detect_call_cycle "$config_file" "$gate_cmd_or_name" "$new_chain"; then
                return 1
            fi
        fi
    done <<< "$gate_definitions"

    return 0
}
