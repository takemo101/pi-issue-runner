#!/usr/bin/env bash
# workflow.sh - ワークフローエンジン

# ワークフロー変数
WORKFLOW_VARS=""

# ワークフロー変数を設定する
# Usage: set_workflow_vars <issue_number> <issue_title> <branch_name> <worktree_path>
set_workflow_vars() {
    local issue_number="$1"
    local issue_title="$2"
    local branch_name="$3"
    local worktree_path="$4"
    
    WORKFLOW_VARS="issue_number=$issue_number"
    WORKFLOW_VARS="$WORKFLOW_VARS issue_title=$issue_title"
    WORKFLOW_VARS="$WORKFLOW_VARS branch_name=$branch_name"
    WORKFLOW_VARS="$WORKFLOW_VARS worktree_path=$worktree_path"
}

# ビルトインワークフローディレクトリを取得
get_builtin_workflow_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_dir/../workflows"
}

# ビルトインエージェントディレクトリを取得
get_builtin_agent_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_dir/../agents"
}

# ワークフローファイルを検索する（優先順位順）
# Usage: find_workflow_file <workflow_name> [project_root]
# 優先順位:
#   1. プロジェクトルートの .pi-runner.yaml
#   2. プロジェクトルートの .pi/workflow.yaml
#   3. ビルトインワークフロー
find_workflow_file() {
    local workflow_name="$1"
    local project_root="${2:-.}"
    
    # デフォルト名の設定
    if [[ -z "$workflow_name" ]]; then
        workflow_name="default"
    fi
    
    # 1. プロジェクトルートの .pi-runner.yaml
    if [[ -f "$project_root/.pi-runner.yaml" ]]; then
        echo "$project_root/.pi-runner.yaml"
        return 0
    fi
    
    # 2. プロジェクトルートの .pi/workflow.yaml
    if [[ -f "$project_root/.pi/workflow.yaml" ]]; then
        echo "$project_root/.pi/workflow.yaml"
        return 0
    fi
    
    # 3. ビルトインワークフロー
    local builtin_dir
    builtin_dir="$(get_builtin_workflow_dir)"
    
    if [[ -f "$builtin_dir/${workflow_name}.yaml" ]]; then
        echo "$builtin_dir/${workflow_name}.yaml"
        return 0
    fi
    
    # 見つからない場合はデフォルトにフォールバック
    if [[ "$workflow_name" != "default" ]] && [[ -f "$builtin_dir/default.yaml" ]]; then
        log_warn "Workflow '$workflow_name' not found, using default"
        echo "$builtin_dir/default.yaml"
        return 0
    fi
    
    log_error "Workflow file not found: $workflow_name"
    return 1
}

# エージェントファイルを検索する
# Usage: find_agent_file <step_name> [project_root]
find_agent_file() {
    local step_name="$1"
    local project_root="${2:-.}"
    
    # 1. プロジェクトルートのagents
    if [[ -f "$project_root/.pi/agents/${step_name}.md" ]]; then
        echo "$project_root/.pi/agents/${step_name}.md"
        return 0
    fi
    
    if [[ -f "$project_root/agents/${step_name}.md" ]]; then
        echo "$project_root/agents/${step_name}.md"
        return 0
    fi
    
    # 2. ビルトインエージェント
    local builtin_dir
    builtin_dir="$(get_builtin_agent_dir)"
    
    if [[ -f "$builtin_dir/${step_name}.md" ]]; then
        echo "$builtin_dir/${step_name}.md"
        return 0
    fi
    
    log_error "Agent file not found: $step_name"
    return 1
}

# テンプレート変数を展開する
# Usage: render_template <template_content> <issue_number> <issue_title> <branch_name> <worktree_path>
render_template() {
    local content="$1"
    local issue_number="$2"
    local issue_title="$3"
    local branch_name="$4"
    local worktree_path="$5"
    
    # テンプレート変数を置換
    content="${content//\{\{issue_number\}\}/$issue_number}"
    content="${content//\{\{issue_title\}\}/$issue_title}"
    content="${content//\{\{branch_name\}\}/$branch_name}"
    content="${content//\{\{worktree_path\}\}/$worktree_path}"
    
    echo "$content"
}

# ワークフローからステップ一覧を取得する
# Usage: get_workflow_steps <workflow_file>
get_workflow_steps() {
    local workflow_file="$1"
    
    # yqがインストールされているか確認
    if command -v yq &>/dev/null; then
        yq -r '.steps[]' "$workflow_file" 2>/dev/null
    else
        # yqがない場合はgrepでパース（シンプルなYAML向け）
        grep -E '^\s*-\s+\w+' "$workflow_file" | sed 's/^[[:space:]]*-[[:space:]]*//'
    fi
}

# ワークフロー名を取得する
# Usage: get_workflow_name <workflow_file>
get_workflow_name() {
    local workflow_file="$1"
    
    if command -v yq &>/dev/null; then
        yq -r '.name // "default"' "$workflow_file" 2>/dev/null
    else
        grep -E '^name:' "$workflow_file" | sed 's/^name:[[:space:]]*//' | head -1
    fi
}

# ワークフロー説明を取得する
# Usage: get_workflow_description <workflow_file>
get_workflow_description() {
    local workflow_file="$1"
    
    if command -v yq &>/dev/null; then
        yq -r '.description // ""' "$workflow_file" 2>/dev/null
    else
        grep -E '^description:' "$workflow_file" | sed 's/^description:[[:space:]]*//' | head -1
    fi
}

# 利用可能なワークフロー一覧を取得する
# Usage: list_available_workflows [project_root]
list_available_workflows() {
    local project_root="${1:-.}"
    local builtin_dir
    builtin_dir="$(get_builtin_workflow_dir)"
    
    # ビルトインワークフロー
    if [[ -d "$builtin_dir" ]]; then
        for f in "$builtin_dir"/*.yaml; do
            if [[ -f "$f" ]]; then
                local name
                name="$(basename "$f" .yaml)"
                local desc
                desc="$(get_workflow_description "$f")"
                echo "$name: $desc"
            fi
        done
    fi
    
    # プロジェクト固有のワークフロー
    if [[ -f "$project_root/.pi-runner.yaml" ]]; then
        echo "custom: (project .pi-runner.yaml)"
    fi
    if [[ -f "$project_root/.pi/workflow.yaml" ]]; then
        echo "custom: (project .pi/workflow.yaml)"
    fi
}

# ワークフロープロンプトを生成する
# Usage: generate_workflow_prompt <workflow_name> <issue_number> <issue_title> <issue_body> <branch_name> <worktree_path> [project_root]
generate_workflow_prompt() {
    local workflow_name="$1"
    local issue_number="$2"
    local issue_title="$3"
    local issue_body="$4"
    local branch_name="$5"
    local worktree_path="$6"
    local project_root="${7:-.}"
    
    # ワークフローファイルを取得
    local workflow_file
    workflow_file="$(find_workflow_file "$workflow_name" "$project_root")" || return 1
    
    # ステップを取得
    local steps
    steps="$(get_workflow_steps "$workflow_file")"
    
    if [[ -z "$steps" ]]; then
        log_error "No steps found in workflow: $workflow_file"
        return 1
    fi
    
    # プロンプトの生成開始
    local prompt=""
    prompt+="Implement GitHub Issue #$issue_number\n\n"
    prompt+="## Title\n$issue_title\n\n"
    prompt+="## Description\n$issue_body\n\n"
    prompt+="---\n\n"
    prompt+="## Workflow: $(get_workflow_name "$workflow_file")\n\n"
    
    local step_num=1
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        
        local agent_file
        agent_file="$(find_agent_file "$step" "$project_root")" || continue
        
        local agent_content
        agent_content="$(cat "$agent_file")"
        
        # テンプレート変数を展開
        agent_content="$(render_template "$agent_content" "$issue_number" "$issue_title" "$branch_name" "$worktree_path")"
        
        # 最初の文字を大文字にする
        local step_name
        step_name="$(echo "$step" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        prompt+="\n## Step $step_num: $step_name\n\n"
        prompt+="$agent_content\n"
        
        ((step_num++))
    done <<< "$steps"
    
    # プロンプトを出力
    echo -e "$prompt"
}

# ワークフロープロンプトをファイルに書き出す
# Usage: write_workflow_prompt <output_file> <workflow_name> <issue_number> <issue_title> <issue_body> <branch_name> <worktree_path> [project_root]
write_workflow_prompt() {
    local output_file="$1"
    shift
    
    local prompt
    prompt="$(generate_workflow_prompt "$@")" || return 1
    
    echo -e "$prompt" > "$output_file"
    log_debug "Workflow prompt written to: $output_file"
}
