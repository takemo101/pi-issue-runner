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
# デフォルトワークフロー解決
# ===================

# -w 未指定時のデフォルトワークフロー名を決定
# .pi-runner.yaml に workflows セクションがあれば "auto"、なければ "default"
# Usage: resolve_default_workflow [project_root]
resolve_default_workflow() {
    local project_root="${1:-.}"
    local config_file="$project_root/.pi-runner.yaml"
    
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows"; then
        echo "auto"
    else
        echo "default"
    fi
}

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
    local config_file="$project_root/.pi-runner.yaml"
    
    # ビルトインと設定ファイルのワークフローを収集
    declare -A workflows  # 連想配列（名前 → description）
    
    # ビルトインワークフロー
    workflows["default"]="完全なワークフロー（計画・実装・レビュー・マージ）"
    workflows["simple"]="簡易ワークフロー（実装・マージのみ）"
    workflows["thorough"]="徹底ワークフロー（計画・実装・テスト・レビュー・マージ）"
    workflows["ci-fix"]="CI失敗を検出し自動修正を試行"
    
    # .pi-runner.yaml の workflows セクション（存在する場合）
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows"; then
        while IFS= read -r name; do
            if [[ -n "$name" ]]; then
                # description を取得（なければデフォルトメッセージ）
                local desc
                desc=$(yaml_get "$config_file" ".workflows.${name}.description" "(project workflow)")
                workflows["$name"]="$desc"
            fi
        done < <(yaml_get_keys "$config_file" ".workflows")
    fi
    
    # プロジェクト固有のワークフローファイル（workflows/*.yaml）
    if [[ -d "$project_root/workflows" ]]; then
        for f in "$project_root/workflows"/*.yaml; do
            if [[ -f "$f" ]]; then
                local name
                name="$(basename "$f" .yaml)"
                # .pi-runner.yaml で定義済みでなければ追加
                if [[ -z "${workflows[$name]:-}" ]]; then
                    workflows["$name"]="(custom workflow file)"
                fi
            fi
        done
    fi
    
    # ソートして出力
    for name in $(printf '%s\n' "${!workflows[@]}" | sort); do
        echo "$name: ${workflows[$name]}"
    done
}
