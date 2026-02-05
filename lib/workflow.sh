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
# ワークフロー管理
# ===================

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
    
    # ビルトインワークフローを明示的に表示
    echo "default: 完全なワークフロー（計画・実装・レビュー・マージ）"
    echo "simple: 簡易ワークフロー（実装・マージのみ）"
    echo "thorough: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）"
    echo "ci-fix: CI失敗を検出し自動修正を試行"
    
    # プロジェクト固有のワークフロー
    if [[ -d "$project_root/workflows" ]]; then
        for f in "$project_root/workflows"/*.yaml; do
            if [[ -f "$f" ]]; then
                local name
                name="$(basename "$f" .yaml)"
                # ビルトインワークフローを除外
                if [[ "$name" != "default" && "$name" != "simple" && "$name" != "thorough" && "$name" != "ci-fix" ]]; then
                    echo "$name: (custom workflow)"
                fi
            fi
        done
    fi
}
