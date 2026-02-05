#!/usr/bin/env bash
# workflow-prompt.sh - ワークフロープロンプト生成

set -euo pipefail

_WORKFLOW_PROMPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_PROMPT_LIB_DIR/log.sh"

# コンテキスト管理をロード（存在する場合）
if [[ -f "$_WORKFLOW_PROMPT_LIB_DIR/context.sh" ]]; then
    source "$_WORKFLOW_PROMPT_LIB_DIR/context.sh"
fi

# Note: find_agent_file, get_agent_prompt, find_workflow_file, get_workflow_steps
# are expected to be loaded by workflow.sh before this file

# ===================
# プロンプト生成
# ===================

# ワークフロープロンプトを生成する
# Usage: generate_workflow_prompt <workflow_name> <issue_number> <issue_title> <issue_body> <branch_name> <worktree_path> [project_root] [issue_comments] [pr_number]
generate_workflow_prompt() {
    local workflow_name="${1:-default}"
    local issue_number="$2"
    local issue_title="$3"
    local issue_body="$4"
    local branch_name="$5"
    local worktree_path="$6"
    local project_root="${7:-.}"
    local issue_comments="${8:-}"
    local pr_number="${9:-}"
    
    # ワークフローファイル検索
    local workflow_file
    workflow_file=$(find_workflow_file "$workflow_name" "$project_root")
    
    # ステップ一覧取得
    local steps
    steps=$(get_workflow_steps "$workflow_file")
    
    # プロンプトヘッダー
    cat << EOF
Implement GitHub Issue #$issue_number

> **⚡ AUTONOMOUS EXECUTION MODE**
> This session runs fully automatically. You MUST:
> - **NOT wait for user input**
> - **NOT ask for confirmation**
> - **NOT ask questions**
> - Proceed immediately to the next step after completing each task
> - Make best-effort decisions when uncertain
> - Execute autonomously until completion without stopping

> **🚫 PROHIBITED ACTIONS**
> - **Do NOT run \`gh issue close\`** - Issues are closed automatically via PR merge with \`Closes #xxx\`
> - **Do NOT open editors** - Use \`git commit -m\`, \`git merge --no-edit\`, \`gh pr create --body\`
> - **Do NOT use interactive commands**

## Title
$issue_title

## Description
$issue_body
EOF
    
    # コンテキストセクションを追加（コンテキストがある場合のみ）
    if declare -f load_all_context > /dev/null 2>&1; then
        local context_content
        context_content="$(load_all_context "$issue_number" 2>/dev/null || true)"
        
        if [[ -n "$context_content" ]]; then
            cat << EOF

## 過去のコンテキスト

$context_content
EOF
        fi
    fi
    
    # コメントセクションを追加（コメントがある場合のみ）
    if [[ -n "$issue_comments" ]]; then
        cat << EOF

## Comments

$issue_comments
EOF
    fi
    
    cat << EOF

---

## Workflow: $workflow_name

You are implementing GitHub Issue #$issue_number in an isolated worktree.
Follow the workflow steps below.

EOF
    
    # 各ステップのプロンプトを生成
    local step_num=1
    for step in $steps; do
        local agent_file
        agent_file=$(find_agent_file "$step" "$project_root")
        
        local agent_prompt
        agent_prompt=$(get_agent_prompt "$agent_file" "$issue_number" "$branch_name" "$worktree_path" "$step" "$issue_title" "$pr_number")
        
        # ステップ名の最初を大文字に
        local step_name
        step_name="$(echo "$step" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        
        echo "### Step $step_num: $step_name"
        echo ""
        echo "$agent_prompt"
        echo ""
        
        ((step_num++)) || true
    done
    
    # フッター（コミット情報）
    cat << EOF
---

### Commit Types
- feat: New feature
- fix: Bug fix
- docs: Documentation
- refactor: Code refactoring
- test: Adding tests
- chore: Maintenance

### On Error
- If tests fail, fix the issue before committing
- If PR merge fails, report the error
- **For unrecoverable errors**, output the error marker:
  - Prefix: \`###TASK\`
  - Middle: \`_ERROR_\`
  - Issue number: \`${issue_number}\`
  - Suffix: \`###\`

This will notify the user and allow manual intervention.

### On Completion
**CRITICAL**: After completing all workflow steps (including PR merge), you MUST output the completion marker.

The marker format combines these parts (no spaces):
- Prefix: \`###TASK\`
- Middle: \`_COMPLETE_\`
- Issue number: \`${issue_number}\`
- Suffix: \`###\`

Combine them and output as a single line. This marker is monitored by an external process that will automatically clean up the worktree and terminate this tmux session.

Do NOT skip this step.
EOF
}

# ワークフロープロンプトをファイルに書き出す
# Usage: write_workflow_prompt <output_file> <workflow_name> <issue_number> <issue_title> <issue_body> <branch_name> <worktree_path> [project_root] [issue_comments] [pr_number]
write_workflow_prompt() {
    local output_file="$1"
    local workflow_name="$2"
    local issue_number="$3"
    local issue_title="$4"
    local issue_body="$5"
    local branch_name="$6"
    local worktree_path="$7"
    local project_root="${8:-.}"
    local issue_comments="${9:-}"
    local pr_number="${10:-}"
    
    generate_workflow_prompt "$workflow_name" "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$worktree_path" "$project_root" "$issue_comments" "$pr_number" > "$output_file"
    
    log_debug "Workflow prompt written to: $output_file"
}
