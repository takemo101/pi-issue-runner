#!/usr/bin/env bash
# workflow.sh - ワークフローエンジン（ステップ・ワークフロー実行）
#
# このファイルは以下のモジュールを統合します:
#   - workflow-finder.sh: ワークフロー・エージェントファイル検索
#   - workflow-loader.sh: ワークフロー読み込み・解析
#   - workflow-prompt.sh: プロンプト生成

set -euo pipefail

_WORKFLOW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# モジュール読み込み
source "$_WORKFLOW_LIB_DIR/workflow-finder.sh"
source "$_WORKFLOW_LIB_DIR/workflow-loader.sh"
source "$_WORKFLOW_LIB_DIR/config.sh"
source "$_WORKFLOW_LIB_DIR/log.sh"
# workflow-prompt.sh は finder と loader に依存するため最後に読み込む
source "$_WORKFLOW_LIB_DIR/workflow-prompt.sh"

# ===================
# ステップ実行
# ===================

# ステップ結果の定数（外部から参照される可能性があるためexport）
export STEP_RESULT_DONE="DONE"
export STEP_RESULT_BLOCKED="BLOCKED"
export STEP_RESULT_FIX_NEEDED="FIX_NEEDED"
export STEP_RESULT_UNKNOWN="UNKNOWN"  # 将来の拡張用

# エージェント出力から結果を判定
parse_step_result() {
    local output="$1"
    
    # 出力から結果マーカーを検出
    if echo "$output" | grep -q '\[DONE\]'; then
        echo "$STEP_RESULT_DONE"
    elif echo "$output" | grep -q '\[BLOCKED\]'; then
        echo "$STEP_RESULT_BLOCKED"
    elif echo "$output" | grep -q '\[FIX_NEEDED\]'; then
        echo "$STEP_RESULT_FIX_NEEDED"
    else
        # マーカーがない場合はDONEとみなす（後方互換性）
        echo "$STEP_RESULT_DONE"
    fi
}

# 単一ステップ実行
# 注: この関数はエージェントプロンプトを返す（実際の実行は呼び出し元で行う）
run_step() {
    local step_name="$1"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local project_root="${5:-.}"
    local issue_title="${6:-}"
    
    log_info "Running step: $step_name"
    
    # エージェントファイル検索
    local agent_file
    agent_file=$(find_agent_file "$step_name" "$project_root")
    log_debug "Agent file: $agent_file"
    
    # プロンプト取得
    local prompt
    prompt=$(get_agent_prompt "$agent_file" "$issue_number" "$branch_name" "$worktree_path" "$step_name" "$issue_title")
    
    echo "$prompt"
}

# ===================
# ワークフロー実行
# ===================

# ワークフロー全体実行
# この関数は実行計画を出力する（実際の実行は呼び出し元で行う）
run_workflow() {
    local workflow_name="${1:-default}"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local project_root="${5:-.}"
    
    log_info "Starting workflow: $workflow_name"
    
    # ワークフローファイル検索
    local workflow_file
    workflow_file=$(find_workflow_file "$workflow_name" "$project_root")
    log_debug "Workflow file: $workflow_file"
    
    # ステップ一覧取得
    local steps
    steps=$(get_workflow_steps "$workflow_file")
    log_info "Steps: $steps"
    
    # 各ステップの情報を出力
    local step_index=0
    for step in $steps; do
        echo "step:$step_index:$step"
        ((step_index++)) || true
    done
    
    echo "total:$step_index"
}

# ワークフローステップを配列として取得
get_workflow_steps_array() {
    local workflow_name="${1:-default}"
    local project_root="${2:-.}"
    
    local workflow_file
    workflow_file=$(find_workflow_file "$workflow_name" "$project_root")
    
    get_workflow_steps "$workflow_file"
}

# ===================
# ワークフロー一覧
# ===================

# 利用可能なワークフロー一覧を表示
list_available_workflows() {
    local project_root="${1:-.}"
    
    echo "default: 完全ワークフロー（計画・実装・レビュー・マージ）"
    echo "simple: 簡易ワークフロー（実装・マージのみ）"
    
    # プロジェクト固有のワークフロー
    if [[ -d "$project_root/workflows" ]]; then
        for f in "$project_root/workflows"/*.yaml; do
            if [[ -f "$f" ]]; then
                local name
                name="$(basename "$f" .yaml)"
                if [[ "$name" != "default" && "$name" != "simple" ]]; then
                    echo "$name: (custom workflow)"
                fi
            fi
        done
    fi
}
