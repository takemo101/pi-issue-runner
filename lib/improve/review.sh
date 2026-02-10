#!/usr/bin/env bash
# ============================================================================
# improve/review.sh - Review phase for improve workflow
#
# Handles project review using pi --print command and Issue creation monitoring.
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_REVIEW_SH_SOURCED:-}" ]]; then
    return 0
fi
_REVIEW_SH_SOURCED="true"

_REVIEW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Find review prompt template file
# Search order:
#   1. .pi-runner.yaml の improve.review_prompt_file
#   2. agents/improve-review.md（プロジェクトローカル）
#   3. .pi/agents/improve-review.md
#   4. pi-issue-runner の agents/improve-review.md
#   5. "" (ビルトインプロンプトにフォールバック)
# Output: file path or empty string
# ============================================================================
_find_review_prompt_file() {
    local project_root="${1:-.}"

    # 1. 設定ファイルで明示指定
    local config_path
    config_path="$(get_config improve_review_prompt_file)" || config_path=""
    if [[ -n "$config_path" ]]; then
        local resolved
        if [[ "$config_path" = /* ]]; then
            resolved="$config_path"
        else
            resolved="$project_root/$config_path"
        fi
        if [[ -f "$resolved" ]]; then
            echo "$resolved"
            return 0
        fi
        log_warn "Configured review prompt file not found: $config_path"
    fi

    # 2. agents/improve-review.md（プロジェクトローカル）
    if [[ -f "$project_root/agents/improve-review.md" ]]; then
        echo "$project_root/agents/improve-review.md"
        return 0
    fi

    # 3. .pi/agents/improve-review.md
    if [[ -f "$project_root/.pi/agents/improve-review.md" ]]; then
        echo "$project_root/.pi/agents/improve-review.md"
        return 0
    fi

    # 4. pi-issue-runner インストールディレクトリ
    local builtin_dir="${_REVIEW_LIB_DIR}/../../agents"
    if [[ -f "$builtin_dir/improve-review.md" ]]; then
        echo "$builtin_dir/improve-review.md"
        return 0
    fi

    # 5. ビルトイン（ハードコード）
    echo ""
}

# Render review prompt template with variable substitution
# Variables: {{max_issues}}, {{session_label}}, {{review_context}}
# Arguments: $1=template, $2=max_issues, $3=session_label, $4=review_context
_render_review_prompt() {
    local template="$1"
    local max_issues="$2"
    local session_label="$3"
    local review_context="$4"

    local result="$template"
    result="${result//\{\{max_issues\}\}/$max_issues}"
    result="${result//\{\{session_label\}\}/$session_label}"
    result="${result//\{\{review_context\}\}/$review_context}"
    echo "$result"
}

# ============================================================================
# Collect context for review phase
# Gathers: recent changes, open issues, previous iteration results
# Arguments: $1=session_label, $2=log_file (previous iteration log, if exists)
# Output: context string to stdout
# ============================================================================
_collect_review_context() {
    local session_label="$1"
    local log_dir="${2:-}"
    local context=""

    # 1. 最近の変更（直近20コミット）
    local recent_commits=""
    if git rev-parse --git-dir &>/dev/null; then
        recent_commits=$(git log --oneline -20 2>/dev/null) || recent_commits=""
    fi
    if [[ -n "$recent_commits" ]]; then
        context+="
## 最近のコミット（直近20件）
以下は最近マージ・コミットされた変更です。これらで修正済みの問題は報告しないでください。
\`\`\`
${recent_commits}
\`\`\`
"
    fi

    # 2. 既存のopen Issue一覧
    local open_issues=""
    if command -v gh &>/dev/null; then
        open_issues=$(gh issue list --state open --limit 20 --json number,title \
            -q '.[] | "#\(.number) \(.title)"' 2>/dev/null) || open_issues=""
    fi
    if [[ -n "$open_issues" ]]; then
        context+="
## 既存のopen Issue（重複禁止）
以下のIssueは既に存在します。同じ内容や類似する問題のIssueを作成しないでください。
\`\`\`
${open_issues}
\`\`\`
"
    fi

    # 3. 前回のイテレーション結果（ログファイルがあれば要約を含める）
    if [[ -n "$log_dir" && -d "$log_dir" ]]; then
        # 最新のログファイルを取得
        local prev_log
        prev_log=$(find "$log_dir" -name "*.log" -type f 2>/dev/null | sort -r | head -1) || prev_log=""
        if [[ -n "$prev_log" && -f "$prev_log" ]]; then
            # ログから作成されたIssueとその結果を抽出（末尾100行）
            local prev_summary
            prev_summary=$(tail -100 "$prev_log" 2>/dev/null | grep -E "(Created issue|gh issue create|PHASE|✅|❌|⚠️)" | head -20) || prev_summary=""
            if [[ -n "$prev_summary" ]]; then
                context+="
## 前回のイテレーション結果
以下は前回のレビュー結果の抜粋です。同じ問題を繰り返し報告しないでください。
前回見つかった問題が修正されていない場合のみ、再度報告してください。
\`\`\`
${prev_summary}
\`\`\`
"
            fi
        fi
    fi

    # 4. AGENTS.md の既知の制約
    local agents_constraints=""
    if [[ -f "AGENTS.md" ]]; then
        agents_constraints=$(sed -n '/## 既知の制約/,/^## /p' "AGENTS.md" 2>/dev/null | head -20) || agents_constraints=""
        if [[ -n "$agents_constraints" ]]; then
            context+="
## 既知の制約（意図的な設計判断）
以下は意図的な制約です。これらを問題として報告しないでください。
${agents_constraints}
"
        fi
    fi

    echo "$context"
}

# ============================================================================
# Execute project review using pi --print
# Arguments: $1=max_issues, $2=session_label, $3=log_file, $4=dry_run,
#            $5=review_only
# Exits: Early exit (0) for --dry-run or --review-only modes
# ============================================================================
run_improve_review_phase() {
    local max_issues="$1"
    local session_label="$2"
    local log_file="$3"
    local dry_run="$4"
    local review_only="$5"

    local pi_command
    pi_command="$(get_config pi_command)"

    # コンテキスト収集（最近の変更、既存Issue、前回の結果）
    local log_dir
    log_dir="$(get_config improve_logs_dir)"
    local review_context
    review_context=$(_collect_review_context "$session_label" "$log_dir")
    log_info "Review context collected (${#review_context} chars)"

    # カスタムレビュープロンプトの検索
    local prompt_file
    prompt_file=$(_find_review_prompt_file ".")

    local prompt
    if [[ -n "$prompt_file" && "$dry_run" != "true" && "$review_only" != "true" ]]; then
        # カスタムテンプレートを使用（dry-run/review-onlyでは使わない）
        log_info "Using custom review prompt: $prompt_file"
        local template
        template=$(cat "$prompt_file")
        prompt=$(_render_review_prompt "$template" "$max_issues" "$session_label" "$review_context")
        echo "[PHASE 1] Running project review via pi --print (custom prompt)..."
    elif [[ "$dry_run" == "true" || "$review_only" == "true" ]]; then
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題を報告してください（最大${max_issues}件）。
【重要】GitHub Issueは作成しないでください。問題の一覧を表示するのみにしてください。
問題が見つからない場合は「問題は見つかりませんでした」と報告してください。
${review_context}"
        echo "[PHASE 1] Running project review via pi --print (dry-run mode)..."
    else
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題からGitHub Issueを作成してください（最大${max_issues}件）。

【重要ルール】
1. Issueを作成する際は、必ず '--label ${session_label}' オプションを使用してラベル '${session_label}' を付けてください。
   例: gh issue create --title \"...\" --body \"...\" --label \"${session_label}\"
2. 既存のopen Issueと重複する問題は作成しないでください。
3. 最近のコミットで修正済みの問題は報告しないでください。
4. 1つのIssueには1つの具体的な問題のみ含めてください（大きなIssueは分割）。
5. Issueには具体的な修正方法、対象ファイル、検証コマンドを含めてください。
6. 問題が見つからない場合は「問題は見つかりませんでした」と報告してください。
${review_context}"
        echo "[PHASE 1] Running project review via pi --print..."
    fi
    echo "[PHASE 1] This may take a few minutes..."
    
    if ! "$pi_command" --print --message "$prompt" 2>&1 | tee "$log_file"; then
        log_warn "pi command returned non-zero exit code"
    fi
    
    echo ""
    echo "[PHASE 1] Review complete. Log saved to: $log_file"
    
    # Hook: レビュー完了（ログファイルから問題数を推定）
    local review_issues_count=0
    if [[ -f "$log_file" ]]; then
        # "gh issue create" または "Created issue" の出現回数をカウント
        review_issues_count=$(grep -cE "(gh issue create|Created issue #)" "$log_file" 2>/dev/null || echo "0")
    fi
    
    if declare -f run_hook &>/dev/null; then
        run_hook "on_review_complete" "" "" "" "" "" "" "" \
            "${_IMPROVE_ITERATION:-1}" "${_IMPROVE_MAX_ITERATIONS:-1}" \
            "" "" "" "$review_issues_count"
    fi

    # Exit early for review-only or dry-run modes
    if [[ "$review_only" == "true" ]]; then
        echo ""
        echo "✅ Review-only mode complete. See log for details: $log_file"
        exit 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "✅ Dry-run mode complete. No Issues were created."
        echo "   Review results saved to: $log_file"
        exit 0
    fi
}
