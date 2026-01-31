#!/usr/bin/env bash
# workflow-finder.sh - ワークフロー・エージェントファイル検索

set -euo pipefail

_WORKFLOW_FINDER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_FINDER_LIB_DIR/yaml.sh"

# ===================
# ファイル検索
# ===================

# ワークフローファイル検索（優先順位順）
# 優先順位:
#   1. .pi-runner.yaml（プロジェクトルート）の workflow セクション
#   2. .pi/workflow.yaml
#   3. workflows/default.yaml
#   4. ビルトイン default
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
    
    # 3. workflows/{name}.yaml
    if [[ -f "$project_root/workflows/${workflow_name}.yaml" ]]; then
        echo "$project_root/workflows/${workflow_name}.yaml"
        return 0
    fi
    
    # 4. ビルトイン（特殊な値で返す）
    echo "builtin:${workflow_name}"
    return 0
}

# エージェントファイル検索
# 優先順位:
#   1. agents/{step}.md
#   2. .pi/agents/{step}.md
#   3. ビルトイン
find_agent_file() {
    local step_name="$1"
    local project_root="${2:-.}"
    
    # 1. agents/{step}.md
    if [[ -f "$project_root/agents/${step_name}.md" ]]; then
        echo "$project_root/agents/${step_name}.md"
        return 0
    fi
    
    # 2. .pi/agents/{step}.md
    if [[ -f "$project_root/.pi/agents/${step_name}.md" ]]; then
        echo "$project_root/.pi/agents/${step_name}.md"
        return 0
    fi
    
    # 3. ビルトイン
    echo "builtin:${step_name}"
    return 0
}
