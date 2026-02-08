#!/usr/bin/env bash
# workflow-prompt.sh - ワークフロープロンプト生成

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_WORKFLOW_PROMPT_SH_SOURCED:-}" ]]; then
    return 0
fi
_WORKFLOW_PROMPT_SH_SOURCED="true"

_WORKFLOW_PROMPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_PROMPT_LIB_DIR/log.sh"

# コンテキスト管理をロード（存在する場合）
if [[ -f "$_WORKFLOW_PROMPT_LIB_DIR/context.sh" ]]; then
    source "$_WORKFLOW_PROMPT_LIB_DIR/context.sh"
fi

# Note: find_agent_file, get_agent_prompt, find_workflow_file, get_workflow_steps
# are expected to be loaded by workflow.sh before this file

# ===================
# プロンプト生成ヘルパー関数
# ===================

# 自律実行モードのヘッダーを出力
_emit_autonomous_header() {
    cat << 'EOF'
> **⚡ AUTONOMOUS EXECUTION MODE**
> This session runs fully automatically. You MUST:
> - **NOT wait for user input**
> - **NOT ask for confirmation**
> - **NOT ask questions**
> - Proceed immediately to the next step after completing each task
> - Make best-effort decisions when uncertain
> - Execute autonomously until completion without stopping

> **🚫 PROHIBITED ACTIONS**
> - **Do NOT run `gh issue close`** - Issues are closed automatically via PR merge with `Closes #xxx`
> - **Do NOT open editors** - Use `git commit -m`, `git merge --no-edit`, `gh pr create --body`
> - **Do NOT use interactive commands**
EOF
}

# Issue ヘッダー（タイトルと説明）を出力
_emit_issue_header() {
    local issue_number="$1"
    local issue_title="$2"
    local issue_body="$3"
    
    cat << EOF
Implement GitHub Issue #$issue_number

EOF
    _emit_autonomous_header
    cat << EOF

## Title
$issue_title

## Description
$issue_body
EOF
}

# コンテキストセクションを出力（コンテキストがある場合のみ）
_emit_context_section() {
    local issue_number="$1"
    
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
}

# コメントセクションを出力（コメントがある場合のみ）
_emit_comments_section() {
    local issue_comments="$1"
    
    if [[ -n "$issue_comments" ]]; then
        cat << EOF

## Comments

$issue_comments
EOF
    fi
}

# フッター（コミットタイプ・エラー・完了）を出力
_emit_prompt_footer() {
    local issue_number="$1"
    
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

# ===================
# プロンプト生成
# ===================

# auto モードのプロンプトを生成する（フォールバック用）
#
# **重要**: この関数は通常は呼ばれません。以下のフォールバックとして機能します：
#
# 通常のフロー（run.sh）:
#   1. run.sh で resolve_auto_workflow_name() を呼び出し、事前にワークフローを選択
#   2. 選択されたワークフロー名で generate_workflow_prompt() を呼び出す
#   3. この時点で workflow_file は具体的なワークフロー名（"quick", "thorough" など）になる
#
# フォールバック（この関数が呼ばれるケース）:
#   1. resolve_auto_workflow_name() が失敗して "auto" を返した場合
#   2. generate_workflow_prompt() に直接 "auto" が渡された場合
#   3. ワークフロー検索で "auto" という名前のファイルが見つかった場合
#
# この関数は全ワークフローの概要テーブルを出力し、AIに選択させます。
# 通常は resolve_auto_workflow_name() による事前選択が推奨されます。
#
_generate_auto_mode_prompt() {
    local issue_number="$1"
    local issue_title="$2"
    local issue_body="$3"
    local branch_name="$4"
    local worktree_path="$5"
    local project_root="${6:-.}"
    local issue_comments="${7:-}"
    local pr_number="${8:-}"
    
    # 全ワークフロー情報を取得
    local workflows_info
    workflows_info=$(get_all_workflows_info "$project_root")
    
    # Issue ヘッダーを出力
    _emit_issue_header "$issue_number" "$issue_title" "$issue_body"
    
    # コンテキストセクションを出力
    _emit_context_section "$issue_number"
    
    # コメントセクションを出力
    _emit_comments_section "$issue_comments"
    
    cat << EOF

---

## Workflow Selection

以下のワークフローから、このIssueに最も適切なものを1つ選択してください。
選択したワークフローの Steps に従い、Context の指示を参考にして実行してください。

### Available Workflows

| Name | Description | Steps |
|------|------------|-------|
EOF
    
    # ワークフロー一覧テーブル
    while IFS=$'\t' read -r name description steps context; do
        if [[ -n "$name" ]]; then
            # steps をスペース区切りから → 区切りに変換
            local steps_display
            steps_display=$(echo "$steps" | sed 's/ / → /g')
            printf "| %s | %s | %s |\n" "$name" "$description" "$steps_display"
        fi
    done < <(echo "$workflows_info")
    
    cat << EOF

### Workflow Details

EOF
    
    # 各ワークフローの詳細
    while IFS=$'\t' read -r name description steps context; do
        if [[ -n "$name" ]]; then
            local steps_display
            steps_display=$(echo "$steps" | sed 's/ / → /g')
            
            # context のエスケープされた改行を復元
            local decoded_context
            decoded_context=$(printf '%s' "$context" | awk '{gsub(/\\n/, "\n"); print}')
            
            # contextを最大300文字に制限（トークン消費削減のため）
            local truncated_context="$decoded_context"
            if [[ -n "$decoded_context" ]] && [[ ${#decoded_context} -gt 300 ]]; then
                truncated_context="${decoded_context:0:300}..."
            fi
            
            cat << EOF
<details>
<summary>$name</summary>

**Description**: $description

**Steps**: $steps_display

EOF
            
            if [[ -n "$truncated_context" ]]; then
                cat << EOF
**Context**:
$truncated_context

EOF
            fi
            
            echo "</details>"
            echo ""
        fi
    done < <(echo "$workflows_info")
    
    cat << EOF

---

**指示**: Issue の内容を分析し、上記から最も適切なワークフローを選択してください。
選択理由を簡潔に述べた後、そのワークフローの Steps と Context に従って実行を開始してください。

## Execution Context

- **Issue番号**: #$issue_number
- **ブランチ**: $branch_name
- **作業ディレクトリ**: $worktree_path
EOF
    
    # フッターを出力
    _emit_prompt_footer "$issue_number"
}

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
    
    # auto モードの場合は特別処理（フォールバックパス）
    # 注意: 通常、run.sh は resolve_auto_workflow_name() で事前にワークフローを選択するため、
    # このコードパスは到達しません。以下の場合のみ実行されます：
    #   - resolve_auto_workflow_name() が失敗して "auto" を返した
    #   - この関数に直接 "auto" が渡された（非推奨）
    if [[ "$workflow_file" == "auto" ]]; then
        _generate_auto_mode_prompt "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$worktree_path" "$project_root" "$issue_comments" "$pr_number"
        return 0
    fi
    
    # ステップ一覧取得
    local steps
    steps=$(get_workflow_steps "$workflow_file")
    
    # Issue ヘッダーを出力
    _emit_issue_header "$issue_number" "$issue_title" "$issue_body"
    
    # コンテキストセクションを出力
    _emit_context_section "$issue_number"
    
    # コメントセクションを出力
    _emit_comments_section "$issue_comments"
    
    cat << EOF

---

## Workflow: $workflow_name

You are implementing GitHub Issue #$issue_number in an isolated worktree.
Follow the workflow steps below.

EOF
    
    # ワークフローコンテキストを取得して注入（存在する場合のみ）
    local workflow_context
    workflow_context="$(get_workflow_context "$workflow_file" 2>/dev/null || true)"
    
    if [[ -n "$workflow_context" ]]; then
        cat << EOF

### Workflow Context

$workflow_context

---

EOF
    fi
    
    # 各ステップのプロンプトを生成
    local step_num=1
    for step in $steps; do
        local agent_file
        agent_file=$(find_agent_file "$step" "$project_root")
        
        local agent_prompt
        agent_prompt=$(get_agent_prompt "$agent_file" "$issue_number" "$branch_name" "$worktree_path" "$step" "$issue_title" "$pr_number" "$workflow_name")
        
        # ステップ名の最初を大文字に
        local step_name
        step_name="$(echo "$step" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        
        echo "### Step $step_num: $step_name"
        echo ""
        echo "$agent_prompt"
        echo ""
        
        ((step_num++)) || true
    done
    
    # フッターを出力
    _emit_prompt_footer "$issue_number"
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
