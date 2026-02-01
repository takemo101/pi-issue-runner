#!/usr/bin/env bash
# workflow-finder.sh - ワークフロー・エージェントファイル検索

set -euo pipefail

_WORKFLOW_FINDER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_FINDER_LIB_DIR/yaml.sh"
source "$_WORKFLOW_FINDER_LIB_DIR/config.sh"

# ===================
# ファイル検索
# ===================

# ワークフローファイル検索（優先順位順）
# 優先順位:
#   1. .pi-runner.yaml（プロジェクトルート）の workflow セクション
#   2. .pi/workflow.yaml
#   3. workflows/{name}.yaml（プロジェクトローカル）
#   4. pi-issue-runnerインストールディレクトリのworkflows/{name}.yaml
#   5. ビルトイン default
find_workflow_file() {
    local workflow_name="${1:-default}"
    local project_root="${2:-.}"
    
    # 1. .pi-runner.yaml の存在確認
    if [[ -f "$project_root/.pi-runner.yaml" ]]; then
        if yaml_exists "$project_root/.pi-runner.yaml" ".workflow"; then
            echo "$project_root/.pi-runner.yaml"
            return 0
        fi
    fi
    
    # 2. .pi/workflow.yaml
    if [[ -f "$project_root/.pi/workflow.yaml" ]]; then
        echo "$project_root/.pi/workflow.yaml"
        return 0
    fi
    
    # 3. workflows/{name}.yaml（プロジェクトローカル）
    if [[ -f "$project_root/workflows/${workflow_name}.yaml" ]]; then
        echo "$project_root/workflows/${workflow_name}.yaml"
        return 0
    fi
    
    # 4. pi-issue-runnerインストールディレクトリのworkflows/{name}.yaml
    local pi_runner_workflows_dir="${_WORKFLOW_FINDER_LIB_DIR}/../workflows"
    if [[ -f "$pi_runner_workflows_dir/${workflow_name}.yaml" ]]; then
        echo "$pi_runner_workflows_dir/${workflow_name}.yaml"
        return 0
    fi
    
    # 5. ビルトイン（特殊な値で返す）
    echo "builtin:${workflow_name}"
    return 0
}

# エージェントファイル検索
# 優先順位:
#   1. 設定ファイルの agents.{step} で指定されたパス（存在する場合）
#   2. agents/{step}.md（プロジェクトローカル）
#   3. .pi/agents/{step}.md（プロジェクトローカル）
#   4. pi-issue-runnerインストールディレクトリのagents/{step}.md
#   5. ビルトイン（ハードコードされた最小限プロンプト）
find_agent_file() {
    local step_name="$1"
    local project_root="${2:-.}"
    
    # 設定を読み込み
    load_config
    
    # 設定からカスタムパスを取得
    local config_path=""
    case "$step_name" in
        plan)
            config_path="$(get_config agents_plan)"
            ;;
        implement)
            config_path="$(get_config agents_implement)"
            ;;
        review)
            config_path="$(get_config agents_review)"
            ;;
        merge)
            config_path="$(get_config agents_merge)"
            ;;
    esac
    
    # 1. 設定ファイルで指定されたパス（相対パスの場合はproject_rootから解決）
    if [[ -n "$config_path" ]]; then
        local resolved_path
        if [[ "$config_path" = /* ]]; then
            # 絶対パスの場合
            resolved_path="$config_path"
        else
            # 相対パスの場合
            resolved_path="$project_root/$config_path"
        fi
        
        if [[ -f "$resolved_path" ]]; then
            echo "$resolved_path"
            return 0
        fi
    fi
    
    # 2. agents/{step}.md（プロジェクトローカル）
    if [[ -f "$project_root/agents/${step_name}.md" ]]; then
        echo "$project_root/agents/${step_name}.md"
        return 0
    fi
    
    # 3. .pi/agents/{step}.md（プロジェクトローカル）
    if [[ -f "$project_root/.pi/agents/${step_name}.md" ]]; then
        echo "$project_root/.pi/agents/${step_name}.md"
        return 0
    fi
    
    # 4. pi-issue-runnerインストールディレクトリのagents/{step}.md
    # _WORKFLOW_FINDER_LIB_DIR は lib/ を指すので、親ディレクトリのagents/を参照
    local pi_runner_agents_dir="${_WORKFLOW_FINDER_LIB_DIR}/../agents"
    if [[ -f "$pi_runner_agents_dir/${step_name}.md" ]]; then
        echo "$pi_runner_agents_dir/${step_name}.md"
        return 0
    fi
    
    # 5. ビルトイン（ハードコードされた最小限プロンプト）
    echo "builtin:${step_name}"
    return 0
}
