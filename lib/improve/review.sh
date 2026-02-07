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

    local prompt
    if [[ "$dry_run" == "true" || "$review_only" == "true" ]]; then
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題を報告してください（最大${max_issues}件）。
【重要】GitHub Issueは作成しないでください。問題の一覧を表示するのみにしてください。
問題が見つからない場合は「問題は見つかりませんでした」と報告してください。"
        echo "[PHASE 1] Running project review via pi --print (dry-run mode)..."
    else
        prompt="project-reviewスキルを読み込んで実行し、プロジェクト全体をレビューしてください。
発見した問題からGitHub Issueを作成してください（最大${max_issues}件）。
【重要】Issueを作成する際は、必ず '--label ${session_label}' オプションを使用してラベル '${session_label}' を付けてください。
例: gh issue create --title \"...\" --body \"...\" --label \"${session_label}\"
Issueを作成しない場合は「問題は見つかりませんでした」と報告してください。"
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

# Backward compatibility: keep old function name
run_review_phase() {
    run_improve_review_phase "$@"
}
