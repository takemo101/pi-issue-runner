#!/usr/bin/env bash
# workflow-loader.sh - ワークフロー読み込み・解析

set -euo pipefail

_WORKFLOW_LOADER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_LOADER_LIB_DIR/yaml.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/log.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/template.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/config.sh"

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
        load_config
        local config_file
        config_file="$(config_file_found 2>/dev/null)" || config_file=".pi-runner.yaml"
        
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

# ワークフローのコンテキストを取得
get_workflow_context() {
    local workflow_file="$1"
    local workflow_name="${2:-}"
    
    # ビルトインの場合はコンテキストなし
    if [[ "$workflow_file" == builtin:* ]]; then
        echo ""
        return 0
    fi
    
    # config-workflow:NAME 形式の処理（.pi-runner.yaml の workflows.{NAME}.context）
    if [[ "$workflow_file" == config-workflow:* ]]; then
        local workflow_name="${workflow_file#config-workflow:}"
        load_config
        local config_file
        config_file="$(config_file_found 2>/dev/null)" || config_file=".pi-runner.yaml"
        
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
    
    # 設定ファイルのパスを決定
    load_config
    local config_file
    config_file="$(config_file_found 2>/dev/null)" || config_file=".pi-runner.yaml"
    
    # .pi-runner.yaml の workflows セクションが存在するか確認
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows"; then
        # workflows セクション配下のキー一覧を取得
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
                
                # context の改行を \\n にエスケープ（タブ区切り出力で壊れないように）
                local escaped_context
                escaped_context=$(printf '%s' "$context" | awk '{printf "%s", (NR>1 ? "\\n" : "") $0}')
                
                # タブ区切りで出力
                printf "%s\t%s\t%s\t%s\n" "$name" "$description" "$steps" "$escaped_context"
            fi
        done <<< "$workflow_names"
    else
        # workflows セクションが未定義の場合はビルトインワークフローをフォールバック
        local builtin_dir="${_WORKFLOW_LOADER_LIB_DIR}/../workflows"
        
        for workflow_file in "$builtin_dir"/*.yaml; do
            if [[ -f "$workflow_file" ]]; then
                local name
                name=$(yaml_get "$workflow_file" ".name" 2>/dev/null || basename "$workflow_file" .yaml)
                
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
                
                # context の改行を \\n にエスケープ（タブ区切り出力で壊れないように）
                local escaped_context
                escaped_context=$(printf '%s' "$context" | awk '{printf "%s", (NR>1 ? "\\n" : "") $0}')
                
                # タブ区切りで出力
                printf "%s\t%s\t%s\t%s\n" "$name" "$description" "$steps" "$escaped_context"
            fi
        done
    fi
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
    render_template "$prompt" "$issue_number" "$branch_name" "$worktree_path" "$step_name" "default" "$issue_title" "$pr_number" "$plans_dir"
}
