#!/usr/bin/env bash
# template.sh - テンプレート処理（変数展開とビルトインエージェントプロンプト）

set -euo pipefail

# ビルトインエージェントプロンプト（最小限）
_BUILTIN_AGENT_PLAN='Plan the implementation for issue #{{issue_number}}.
Read the issue description and create an implementation plan.'

_BUILTIN_AGENT_IMPLEMENT='Implement the changes for issue #{{issue_number}}.
Follow the plan and make the necessary code changes.'

_BUILTIN_AGENT_REVIEW='Review the implementation for issue #{{issue_number}}.
Check code quality, tests, and documentation.'

_BUILTIN_AGENT_MERGE='Create a PR and merge for issue #{{issue_number}}.
Push changes and create a pull request.'

_BUILTIN_AGENT_TEST='Test the implementation for issue #{{issue_number}}.
Run existing tests and verify all tests pass.'

_BUILTIN_AGENT_CI_FIX='Fix CI failures for issue #{{issue_number}}.
Analyze CI logs, identify the failure, and fix the code.'

# ===================
# テンプレート処理
# ===================

# テンプレート変数展開
# 対応変数:
#   {{issue_number}} - Issue番号
#   {{issue_title}} - Issueタイトル
#   {{branch_name}} - ブランチ名
#   {{worktree_path}} - ワークツリーパス
#   {{step_name}} - 現在のステップ名
#   {{workflow_name}} - ワークフロー名
#   {{pr_number}} - PR番号
#   {{plans_dir}} - 計画書ディレクトリパス
render_template() {
    local template="$1"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local step_name="${5:-}"
    local workflow_name="${6:-default}"
    local issue_title="${7:-}"
    local pr_number="${8:-}"
    local plans_dir="${9:-docs/plans}"
    
    local result="$template"
    
    # 変数展開
    result="${result//\{\{issue_number\}\}/$issue_number}"
    result="${result//\{\{issue_title\}\}/$issue_title}"
    result="${result//\{\{branch_name\}\}/$branch_name}"
    result="${result//\{\{worktree_path\}\}/$worktree_path}"
    result="${result//\{\{step_name\}\}/$step_name}"
    result="${result//\{\{workflow_name\}\}/$workflow_name}"
    result="${result//\{\{pr_number\}\}/$pr_number}"
    result="${result//\{\{plans_dir\}\}/$plans_dir}"
    
    echo "$result"
}
