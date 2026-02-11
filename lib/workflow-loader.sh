#!/usr/bin/env bash
# workflow-loader.sh - ワークフロー読み込み・解析

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_WORKFLOW_LOADER_SH_SOURCED:-}" ]]; then
    return 0
fi
_WORKFLOW_LOADER_SH_SOURCED="true"

_WORKFLOW_LOADER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_LOADER_LIB_DIR/yaml.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/log.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/template.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/config.sh"

# 設定ファイルのパスを解決して返す
# CONFIG_FILE環境変数が設定されている場合はそれを使用（テスト用）
# 未設定の場合は config_file_found() で自動検索
# Usage: _resolve_config_file
# Output: 設定ファイルのパスを stdout に出力
# Side effect: load_config を呼び出す
_resolve_config_file() {
    if [[ -n "${CONFIG_FILE:-}" ]]; then
        load_config "$CONFIG_FILE"
        echo "$CONFIG_FILE"
    else
        load_config
        config_file_found 2>/dev/null || echo ".pi-runner.yaml"
    fi
}

# ビルトインワークフロー定義
# workflows/ ディレクトリが存在しない場合に使用
_BUILTIN_WORKFLOW_DEFAULT="plan implement review merge"
_BUILTIN_WORKFLOW_SIMPLE="implement merge"

# ===================
# ワークフロー読み込み
# ===================

# ワークフローからステップ一覧を取得
get_workflow_steps() {
    local workflow_file="$1"
    
    # ビルトインの場合
    if [[ "$workflow_file" == builtin:* ]]; then
        local workflow_name="${workflow_file#builtin:}"
        case "$workflow_name" in
            simple)
                echo "$_BUILTIN_WORKFLOW_SIMPLE"
                ;;
            *)
                echo "$_BUILTIN_WORKFLOW_DEFAULT"
                ;;
        esac
        return 0
    fi
    
    # config-workflow:NAME 形式の処理（.pi-runner.yaml の workflows.{NAME}.steps）
    if [[ "$workflow_file" == config-workflow:* ]]; then
        local workflow_name="${workflow_file#config-workflow:}"
        local config_file
        config_file="$(_resolve_config_file)"
        
        if [[ ! -f "$config_file" ]]; then
            log_warn "Config file not found, using builtin"
            echo "$_BUILTIN_WORKFLOW_DEFAULT"
            return 0
        fi
        
        local steps=""
        local yaml_path=".workflows.${workflow_name}.steps"
        
        # 配列を取得してスペース区切りに変換
        while IFS= read -r step; do
            if [[ -n "$step" ]]; then
                if [[ -z "$steps" ]]; then
                    steps="$step"
                else
                    steps="$steps $step"
                fi
            fi
        done < <(yaml_get_array "$config_file" "$yaml_path")
        
        if [[ -z "$steps" ]]; then
            log_warn "No steps found in config-workflow:${workflow_name}, using builtin"
            echo "$_BUILTIN_WORKFLOW_DEFAULT"
            return 0
        fi
        
        echo "$steps"
        return 0
    fi
    
    # ファイルが存在しない場合
    if [[ ! -f "$workflow_file" ]]; then
        log_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    # YAMLからstepsを読み込む（yaml.shを使用）
    local steps=""
    local yaml_path
    
    # .pi-runner.yaml の場合は .workflow.steps を参照
    if [[ "$workflow_file" == *".pi-runner.yaml" ]]; then
        yaml_path=".workflow.steps"
    else
        yaml_path=".steps"
    fi
    
    # 配列を取得してスペース区切りに変換
    while IFS= read -r step; do
        if [[ -n "$step" ]]; then
            if [[ -z "$steps" ]]; then
                steps="$step"
            else
                steps="$steps $step"
            fi
        fi
    done < <(yaml_get_array "$workflow_file" "$yaml_path")
    
    if [[ -z "$steps" ]]; then
        log_warn "No steps found in workflow, using builtin"
        echo "$_BUILTIN_WORKFLOW_DEFAULT"
        return 0
    fi
    
    echo "$steps"
}

# ===================
# 型付きステップ解析（run: 対応）
# ===================

# ワークフローからステップ一覧を型付きで取得
# 各行がタブ区切りで出力される:
#   ai<TAB>step_name
#   run<TAB>command<TAB>timeout<TAB>max_retry<TAB>retry_interval<TAB>continue_on_fail<TAB>description
# Note: call: ステップは廃止されました。検出時は警告を出してスキップします。
#
# Usage: get_workflow_steps_typed <workflow_file>
# Output: 1行1ステップのタブ区切りテキスト
get_workflow_steps_typed() {
    local workflow_file="$1"

    # ビルトインの場合（全て AI ステップ）
    if [[ "$workflow_file" == builtin:* ]]; then
        local workflow_name="${workflow_file#builtin:}"
        local steps_str
        case "$workflow_name" in
            simple) steps_str="$_BUILTIN_WORKFLOW_SIMPLE" ;;
            *)      steps_str="$_BUILTIN_WORKFLOW_DEFAULT" ;;
        esac
        local s
        for s in $steps_str; do
            printf "ai\t%s\n" "$s"
        done
        return 0
    fi

    # config-workflow:NAME 形式
    if [[ "$workflow_file" == config-workflow:* ]]; then
        local workflow_name="${workflow_file#config-workflow:}"
        local config_file
        config_file="$(_resolve_config_file)"

        if [[ ! -f "$config_file" ]]; then
            log_warn "Config file not found, using builtin"
            local s
            for s in $_BUILTIN_WORKFLOW_DEFAULT; do
                printf "ai\t%s\n" "$s"
            done
            return 0
        fi

        _parse_typed_steps_from_config "$config_file" ".workflows.${workflow_name}.steps"
        return $?
    fi

    # ファイル形式のワークフロー
    if [[ ! -f "$workflow_file" ]]; then
        log_error "Workflow file not found: $workflow_file"
        return 1
    fi

    local yaml_path
    if [[ "$workflow_file" == *".pi-runner.yaml" ]]; then
        yaml_path=".workflow.steps"
    else
        yaml_path=".steps"
    fi

    _parse_typed_steps_from_config "$workflow_file" "$yaml_path"
}

# YAML設定ファイルから型付きステップを解析する内部関数
# Usage: _parse_typed_steps_from_config <config_file> <yaml_path>
_parse_typed_steps_from_config() {
    local config_file="$1"
    local yaml_path="$2"
    local found_any=false

    if check_yq; then
        # yq でJSON形式で各要素を取り出す
        local item_json
        while IFS= read -r item_json; do
            [[ -z "$item_json" ]] && continue
            found_any=true

            # 文字列の場合（AIステップ）: "plan" のようにダブルクォート付き
            if [[ "$item_json" == '"'*'"' ]]; then
                local step_name
                step_name="${item_json#\"}"
                step_name="${step_name%\"}"
                printf "ai\t%s\n" "$step_name"
                continue
            fi

            # マップの場合: {"run":"command",...} or {"call":"name",...}
            local run_val call_val timeout max_retry retry_interval continue_on_fail description
            run_val=$(echo "$item_json" | yq -r '.run // ""' - 2>/dev/null) || run_val=""
            call_val=$(echo "$item_json" | yq -r '.call // ""' - 2>/dev/null) || call_val=""
            timeout=$(echo "$item_json" | yq -r '.timeout // "900"' - 2>/dev/null) || timeout="900"
            max_retry=$(echo "$item_json" | yq -r '.max_retry // "0"' - 2>/dev/null) || max_retry="0"
            retry_interval=$(echo "$item_json" | yq -r '.retry_interval // "10"' - 2>/dev/null) || retry_interval="10"
            continue_on_fail=$(echo "$item_json" | yq -r '.continue_on_fail // "false"' - 2>/dev/null) || continue_on_fail="false"
            description=$(echo "$item_json" | yq -r '.description // ""' - 2>/dev/null) || description=""

            if [[ -n "$run_val" ]]; then
                [[ -z "$description" ]] && description="$run_val"
                printf "run\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                    "$run_val" "$timeout" "$max_retry" "$retry_interval" "$continue_on_fail" "$description"
            elif [[ -n "$call_val" ]]; then
                log_warn "call: steps are deprecated and ignored. Use AI steps instead: $call_val"
            else
                log_warn "Unknown step format in $config_file: $item_json"
            fi
        done < <(yq -o=json -I=0 "${yaml_path}[]" "$config_file" 2>/dev/null)
    else
        # yq なし: 簡易パーサーでは run: はサポートしない（AIステップのみ）
        log_warn "yq not available: run: steps require yq. Falling back to AI-only steps."
        while IFS= read -r step; do
            if [[ -n "$step" ]]; then
                found_any=true
                printf "ai\t%s\n" "$step"
            fi
        done < <(yaml_get_array "$config_file" "$yaml_path")
    fi

    if [[ "$found_any" == "false" ]]; then
        log_warn "No steps found, using builtin"
        local s
        for s in $_BUILTIN_WORKFLOW_DEFAULT; do
            printf "ai\t%s\n" "$s"
        done
    fi
}

# 型付きステップからAIステップ名のみを抽出（後方互換用）
# Usage: typed_steps_to_ai_only <typed_steps>
# Input: get_workflow_steps_typed の出力（パイプまたはヒアストリングで渡す）
# Output: スペース区切りのAIステップ名
typed_steps_to_ai_only() {
    local steps=""
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local step_type step_name
        step_type="${line%%	*}"
        if [[ "$step_type" == "ai" ]]; then
            step_name="${line#ai	}"
            step_name="${step_name%%	*}"
            if [[ -z "$steps" ]]; then
                steps="$step_name"
            else
                steps="$steps $step_name"
            fi
        fi
    done
    echo "$steps"
}

# 型付きステップをAIグループとnon-AIグループに分割
# 出力: 各行が group_type<TAB>content の形式
#   ai_group<TAB>plan implement        (スペース区切りのAIステップ名)
#   non_ai_group<TAB><ステップ定義>    (改行区切りの run/call 定義、\n エスケープ)
#   ai_group<TAB>merge
#
# Usage: get_step_groups <typed_steps_input>
# Input: get_workflow_steps_typed の出力（パイプで渡す）
get_step_groups() {
    local current_type=""  # "ai" or "non_ai"
    local current_ai_steps=""
    local current_non_ai_lines=""
    local line

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local step_type
        step_type="${line%%	*}"

        if [[ "$step_type" == "ai" ]]; then
            # non-AI グループが蓄積されていたら出力
            if [[ "$current_type" == "non_ai" && -n "$current_non_ai_lines" ]]; then
                printf "non_ai_group\t%s\n" "$current_non_ai_lines"
                current_non_ai_lines=""
            fi
            # AI ステップを蓄積
            local step_name="${line#ai	}"
            if [[ -z "$current_ai_steps" || "$current_type" != "ai" ]]; then
                # 前のAIグループが残っていたら出力
                if [[ "$current_type" == "ai" && -n "$current_ai_steps" ]]; then
                    printf "ai_group\t%s\n" "$current_ai_steps"
                fi
                current_ai_steps="$step_name"
            else
                current_ai_steps="$current_ai_steps $step_name"
            fi
            current_type="ai"
        else
            # AI グループが蓄積されていたら出力
            if [[ "$current_type" == "ai" && -n "$current_ai_steps" ]]; then
                printf "ai_group\t%s\n" "$current_ai_steps"
                current_ai_steps=""
            fi
            # non-AI ステップを蓄積（改行を\\nでエスケープして1行に）
            if [[ -z "$current_non_ai_lines" ]]; then
                current_non_ai_lines="$line"
            else
                current_non_ai_lines="${current_non_ai_lines}\\n${line}"
            fi
            current_type="non_ai"
        fi
    done

    # 残りを出力
    if [[ "$current_type" == "ai" && -n "$current_ai_steps" ]]; then
        printf "ai_group\t%s\n" "$current_ai_steps"
    elif [[ "$current_type" == "non_ai" && -n "$current_non_ai_lines" ]]; then
        printf "non_ai_group\t%s\n" "$current_non_ai_lines"
    fi
}

# ワークフローのコンテキストを取得
get_workflow_context() {
    local workflow_file="$1"
    
    # ビルトインの場合はコンテキストなし
    if [[ "$workflow_file" == builtin:* ]]; then
        echo ""
        return 0
    fi
    
    # config-workflow:NAME 形式の処理（.pi-runner.yaml の workflows.{NAME}.context）
    if [[ "$workflow_file" == config-workflow:* ]]; then
        local workflow_name="${workflow_file#config-workflow:}"
        local config_file
        config_file="$(_resolve_config_file)"
        
        if [[ ! -f "$config_file" ]]; then
            echo ""
            return 0
        fi
        
        local yaml_path=".workflows.${workflow_name}.context"
        local context
        context=$(yaml_get "$config_file" "$yaml_path" 2>/dev/null || echo "")
        
        echo "$context"
        return 0
    fi
    
    # ファイルが存在しない場合
    if [[ ! -f "$workflow_file" ]]; then
        echo ""
        return 0
    fi
    
    # YAMLファイルから .context キーを取得
    local yaml_path
    
    # .pi-runner.yaml の場合は .workflow.context を参照
    if [[ "$workflow_file" == *".pi-runner.yaml" ]]; then
        yaml_path=".workflow.context"
    else
        yaml_path=".context"
    fi
    
    local context
    context=$(yaml_get "$workflow_file" "$yaml_path" 2>/dev/null || echo "")
    
    echo "$context"
}

# 全ワークフロー情報を取得（auto モード用）
# 出力: name description steps context（1行1ワークフロー、タブ区切り）
get_all_workflows_info() {
    # shellcheck disable=SC2034  # project_root reserved for future use
    local project_root="${1:-.}"
    
    local config_file
    config_file="$(_resolve_config_file)"
    
    # 出力済みワークフロー名を追跡（ユーザー定義を優先するため）
    local -a emitted_names=()
    
    # 1. .pi-runner.yaml の workflows セクション（ユーザー定義、最優先）
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows"; then
        local workflow_names
        workflow_names=$(yaml_get_keys "$config_file" ".workflows")
        
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                local description
                description=$(yaml_get "$config_file" ".workflows.${name}.description" 2>/dev/null || echo "")
                
                local steps=""
                while IFS= read -r step; do
                    if [[ -n "$step" ]]; then
                        if [[ -z "$steps" ]]; then
                            steps="$step"
                        else
                            steps="$steps $step"
                        fi
                    fi
                done < <(yaml_get_array "$config_file" ".workflows.${name}.steps" 2>/dev/null)
                
                local context
                context=$(yaml_get "$config_file" ".workflows.${name}.context" 2>/dev/null || echo "")
                
                local escaped_context
                escaped_context=$(printf '%s' "$context" | awk '{printf "%s", (NR>1 ? "\\n" : "") $0}')
                
                printf "%s\t%s\t%s\t%s\n" "$name" "$description" "$steps" "$escaped_context"
                emitted_names+=("$name")
            fi
        done <<< "$workflow_names"
    fi
    
    # 2. ビルトインワークフロー（ユーザー定義と同名のものはスキップ）
    local builtin_dir="${_WORKFLOW_LOADER_LIB_DIR}/../workflows"
    
    for workflow_file in "$builtin_dir"/*.yaml; do
        if [[ -f "$workflow_file" ]]; then
            local name
            name=$(yaml_get "$workflow_file" ".name" 2>/dev/null || basename "$workflow_file" .yaml)
            
            # ユーザー定義で同名が既に出力されていればスキップ
            local already_emitted=false
            local emitted
            for emitted in "${emitted_names[@]+"${emitted_names[@]}"}"; do
                if [[ "$emitted" == "$name" ]]; then
                    already_emitted=true
                    break
                fi
            done
            if [[ "$already_emitted" == "true" ]]; then
                continue
            fi
            
            local description
            description=$(yaml_get "$workflow_file" ".description" 2>/dev/null || echo "")
            
            local steps=""
            while IFS= read -r step; do
                if [[ -n "$step" ]]; then
                    if [[ -z "$steps" ]]; then
                        steps="$step"
                    else
                        steps="$steps $step"
                    fi
                fi
            done < <(yaml_get_array "$workflow_file" ".steps" 2>/dev/null)
            
            local context
            context=$(yaml_get "$workflow_file" ".context" 2>/dev/null || echo "")
            
            local escaped_context
            escaped_context=$(printf '%s' "$context" | awk '{printf "%s", (NR>1 ? "\\n" : "") $0}')
            
            printf "%s\t%s\t%s\t%s\n" "$name" "$description" "$steps" "$escaped_context"
        fi
    done
}

# ワークフローのagent設定を取得（存在する場合）
# 引数:
#   $1 - workflow_file: ワークフローファイル識別子
#   $2 - property: 取得するプロパティ (type|command|args|template)
# 出力: 設定値（存在しない場合は空文字）
get_workflow_agent_property() {
    local workflow_file="$1"
    local property="$2"
    
    # ビルトインの場合は設定なし
    if [[ "$workflow_file" == builtin:* ]]; then
        echo ""
        return 0
    fi
    
    # config-workflow:NAME 形式の処理
    if [[ "$workflow_file" == config-workflow:* ]]; then
        local workflow_name="${workflow_file#config-workflow:}"
        local config_file
        config_file="$(_resolve_config_file)"
        
        if [[ ! -f "$config_file" ]]; then
            echo ""
            return 0
        fi
        
        local yaml_path=".workflows.${workflow_name}.agent.${property}"
        local value
        
        if [[ "$property" == "args" ]]; then
            # args は配列なのでスペース区切りに変換
            local args=""
            while IFS= read -r arg; do
                if [[ -n "$arg" ]]; then
                    if [[ -z "$args" ]]; then
                        args="$arg"
                    else
                        args="$args $arg"
                    fi
                fi
            done < <(yaml_get_array "$config_file" "$yaml_path" 2>/dev/null)
            value="$args"
        else
            value=$(yaml_get "$config_file" "$yaml_path" 2>/dev/null || echo "")
        fi
        
        echo "$value"
        return 0
    fi
    
    # ファイル形式のワークフロー
    if [[ ! -f "$workflow_file" ]]; then
        echo ""
        return 0
    fi
    
    # YAMLパスを決定
    local yaml_path
    if [[ "$workflow_file" == *".pi-runner.yaml" ]]; then
        yaml_path=".workflow.agent.${property}"
    else
        yaml_path=".agent.${property}"
    fi
    
    local value
    if [[ "$property" == "args" ]]; then
        # args は配列なのでスペース区切りに変換
        local args=""
        while IFS= read -r arg; do
            if [[ -n "$arg" ]]; then
                if [[ -z "$args" ]]; then
                    args="$arg"
                else
                    args="$args $arg"
                fi
            fi
        done < <(yaml_get_array "$workflow_file" "$yaml_path" 2>/dev/null)
        value="$args"
    else
        value=$(yaml_get "$workflow_file" "$yaml_path" 2>/dev/null || echo "")
    fi
    
    echo "$value"
    return 0
}

# エージェントプロンプトを取得
get_agent_prompt() {
    local agent_file="$1"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local step_name="${5:-}"
    local issue_title="${6:-}"
    local pr_number="${7:-}"
    local workflow_name="${8:-default}"
    
    local prompt
    
    # ビルトインの場合
    if [[ "$agent_file" == builtin:* ]]; then
        local agent_name="${agent_file#builtin:}"
        case "$agent_name" in
            plan)
                prompt="$_BUILTIN_AGENT_PLAN"
                ;;
            implement)
                prompt="$_BUILTIN_AGENT_IMPLEMENT"
                ;;
            review)
                prompt="$_BUILTIN_AGENT_REVIEW"
                ;;
            merge)
                prompt="$_BUILTIN_AGENT_MERGE"
                ;;
            test)
                prompt="$_BUILTIN_AGENT_TEST"
                ;;
            ci-fix)
                prompt="$_BUILTIN_AGENT_CI_FIX"
                ;;
            *)
                log_warn "Unknown builtin agent: $agent_name, using implement"
                prompt="$_BUILTIN_AGENT_IMPLEMENT"
                ;;
        esac
    else
        # ファイルから読み込み
        if [[ ! -f "$agent_file" ]]; then
            log_error "Agent file not found: $agent_file"
            return 1
        fi
        prompt=$(cat "$agent_file")
    fi
    
    # 設定から plans_dir を取得
    load_config
    local plans_dir
    plans_dir=$(get_config plans_dir)
    
    # テンプレート変数展開
    render_template "$prompt" "$issue_number" "$branch_name" "$worktree_path" "$step_name" "$workflow_name" "$issue_title" "$pr_number" "$plans_dir"
}

# ワークフロー固有のエージェント設定を取得
# 引数:
#   $1 - workflow_name: ワークフロー名
#   $2 - property: 取得するプロパティ (type|command|args|template)
# 出力: 設定値（未設定の場合は空文字列）
get_workflow_agent_config() {
    local workflow_name="$1"
    local property="$2"
    
    local config_file
    config_file="$(_resolve_config_file)"
    
    if [[ ! -f "$config_file" ]]; then
        echo ""
        return 0
    fi
    
    local yaml_path=".workflows.${workflow_name}.agent.${property}"
    
    # args の場合は配列として取得
    if [[ "$property" == "args" ]]; then
        local args=""
        while IFS= read -r arg; do
            if [[ -n "$arg" ]]; then
                if [[ -z "$args" ]]; then
                    args="$arg"
                else
                    args="$args $arg"
                fi
            fi
        done < <(yaml_get_array "$config_file" "$yaml_path" 2>/dev/null)
        echo "$args"
    else
        # type, command, template はスカラー値
        yaml_get "$config_file" "$yaml_path" 2>/dev/null || echo ""
    fi
}
