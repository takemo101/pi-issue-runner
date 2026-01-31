#!/usr/bin/env bash
# workflow.sh - ワークフローエンジン（YAMLワークフロー定義の読み込みと実行）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/log.sh"

# ビルトインワークフロー定義
# workflows/ ディレクトリが存在しない場合に使用
_BUILTIN_WORKFLOW_DEFAULT="plan implement review merge"
_BUILTIN_WORKFLOW_SIMPLE="implement merge"

# ビルトインエージェントプロンプト（最小限）
_BUILTIN_AGENT_PLAN='Plan the implementation for issue #{{issue_number}}.
Read the issue description and create an implementation plan.'

_BUILTIN_AGENT_IMPLEMENT='Implement the changes for issue #{{issue_number}}.
Follow the plan and make the necessary code changes.'

_BUILTIN_AGENT_REVIEW='Review the implementation for issue #{{issue_number}}.
Check code quality, tests, and documentation.'

_BUILTIN_AGENT_MERGE='Create a PR and merge for issue #{{issue_number}}.
Push changes and create a pull request.'

# ===================
# 依存チェック
# ===================

# yq の存在確認
check_yq() {
    if command -v yq &> /dev/null; then
        return 0
    else
        log_debug "yq not found, using builtin workflow"
        return 1
    fi
}

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
        if check_yq && yq -e '.workflow' "$project_root/.pi-runner.yaml" &>/dev/null; then
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
    
    # ファイルが存在しない場合
    if [[ ! -f "$workflow_file" ]]; then
        log_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    # yq が利用可能か確認
    if ! check_yq; then
        log_warn "yq not available, using builtin workflow"
        echo "$_BUILTIN_WORKFLOW_DEFAULT"
        return 0
    fi
    
    # YAMLからstepsを読み込む
    # .pi-runner.yaml の場合は .workflow.steps を参照
    local steps
    if [[ "$workflow_file" == *".pi-runner.yaml" ]]; then
        steps=$(yq -r '.workflow.steps[]' "$workflow_file" 2>/dev/null | tr '\n' ' ' || echo "")
    else
        steps=$(yq -r '.steps[]' "$workflow_file" 2>/dev/null | tr '\n' ' ' || echo "")
    fi
    
    # 末尾のスペースを削除
    steps="${steps% }"
    
    if [[ -z "$steps" ]]; then
        log_warn "No steps found in workflow, using builtin"
        echo "$_BUILTIN_WORKFLOW_DEFAULT"
        return 0
    fi
    
    echo "$steps"
}

# ===================
# テンプレート処理
# ===================

# テンプレート変数展開
# 対応変数:
#   {{issue_number}} - Issue番号
#   {{branch_name}} - ブランチ名
#   {{worktree_path}} - ワークツリーパス
#   {{step_name}} - 現在のステップ名
#   {{workflow_name}} - ワークフロー名
render_template() {
    local template="$1"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local step_name="${5:-}"
    local workflow_name="${6:-default}"
    
    local result="$template"
    
    # 変数展開
    result="${result//\{\{issue_number\}\}/$issue_number}"
    result="${result//\{\{branch_name\}\}/$branch_name}"
    result="${result//\{\{worktree_path\}\}/$worktree_path}"
    result="${result//\{\{step_name\}\}/$step_name}"
    result="${result//\{\{workflow_name\}\}/$workflow_name}"
    
    echo "$result"
}

# エージェントプロンプトを取得
get_agent_prompt() {
    local agent_file="$1"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local step_name="${5:-}"
    
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
    
    # テンプレート変数展開
    render_template "$prompt" "$issue_number" "$branch_name" "$worktree_path" "$step_name"
}

# ===================
# ステップ実行
# ===================

# ステップ結果の定数
STEP_RESULT_DONE="DONE"
STEP_RESULT_BLOCKED="BLOCKED"
STEP_RESULT_FIX_NEEDED="FIX_NEEDED"
STEP_RESULT_UNKNOWN="UNKNOWN"

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
    
    log_info "Running step: $step_name"
    
    # エージェントファイル検索
    local agent_file
    agent_file=$(find_agent_file "$step_name" "$project_root")
    log_debug "Agent file: $agent_file"
    
    # プロンプト取得
    local prompt
    prompt=$(get_agent_prompt "$agent_file" "$issue_number" "$branch_name" "$worktree_path" "$step_name")
    
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
