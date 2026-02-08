#!/usr/bin/env bash
# workflow-finder.sh - ワークフロー・エージェントファイル検索

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_WORKFLOW_FINDER_SH_SOURCED:-}" ]]; then
    return 0
fi
_WORKFLOW_FINDER_SH_SOURCED="true"

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
#   注意: 通常、run.sh は resolve_auto_workflow_name() で事前にワークフローを選択するため、
#   この関数に "auto" が渡されることは稀です（フォールバック用）。
find_workflow_file() {
    local workflow_name="${1:-default}"
    local project_root="${2:-.}"
    
    # AI自動選択モード（フォールバックパス）
    # 通常は run.sh で resolve_auto_workflow_name() により事前選択されるため、
    # このコードパスが実行されるのは稀です（直接呼び出し時のみ）
    if [[ "$workflow_name" == "auto" ]]; then
        echo "auto"
        return 0
    fi
    
    # 名前付きワークフロー（default含む）: .workflows.{name} を優先検索
    if [[ -f "$project_root/.pi-runner.yaml" ]]; then
        if yaml_exists "$project_root/.pi-runner.yaml" ".workflows.${workflow_name}"; then
            echo "config-workflow:${workflow_name}"
            return 0
        fi
    fi
    
    # デフォルトワークフローの場合: 後方互換で .workflow セクションも検索
    if [[ "$workflow_name" == "default" ]]; then
        if [[ -f "$project_root/.pi-runner.yaml" ]]; then
            if yaml_exists "$project_root/.pi-runner.yaml" ".workflow"; then
                echo "$project_root/.pi-runner.yaml"
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
