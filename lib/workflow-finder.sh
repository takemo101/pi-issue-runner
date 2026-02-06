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
# デフォルトワークフロー（workflow_name="default"）の場合:
#   1. .pi-runner.yaml（プロジェクトルート）の workflow セクション
#   2. .pi/workflow.yaml
#   3. workflows/default.yaml（プロジェクトローカル）
#   4. pi-issue-runnerインストールディレクトリのworkflows/default.yaml
#   5. ビルトイン default
# 名前付きワークフロー（workflow_name != "default"）の場合:
#   1. .pi-runner.yaml の workflows.{name} セクション → config-workflow:{name}
#   2. .pi/workflow.yaml
#   3. workflows/{name}.yaml（プロジェクトローカル）
#   4. pi-issue-runnerインストールディレクトリのworkflows/{name}.yaml
#   5. ビルトイン {name}
# AI自動選択（workflow_name="auto"）の場合:
#   auto をそのまま返す（プロンプト生成側で特別な処理を行う）
find_workflow_file() {
    local workflow_name="${1:-default}"
    local project_root="${2:-.}"
    
    # AI自動選択モード
    if [[ "$workflow_name" == "auto" ]]; then
        echo "auto"
        return 0
    fi
    
    # デフォルトワークフローの場合: 従来通り .workflow セクションを検索
    if [[ "$workflow_name" == "default" ]]; then
        if [[ -f "$project_root/.pi-runner.yaml" ]]; then
            if yaml_exists "$project_root/.pi-runner.yaml" ".workflow"; then
                echo "$project_root/.pi-runner.yaml"
                return 0
            fi
        fi
    else
        # 名前付きワークフローの場合: .workflows.{name} を優先検索
        if [[ -f "$project_root/.pi-runner.yaml" ]]; then
            if yaml_exists "$project_root/.pi-runner.yaml" ".workflows.${workflow_name}"; then
                echo "config-workflow:${workflow_name}"
                return 0
            fi
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
        test)
            config_path="$(get_config agents_test)"
            ;;
        ci-fix)
            config_path="$(get_config agents_ci_fix)"
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
