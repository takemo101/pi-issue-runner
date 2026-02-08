#!/usr/bin/env bash
# ci-fix/escalation.sh - エスカレーション処理
#
# CI自動修正が不可能な場合のエスカレーション処理を提供します。

set -euo pipefail

# ソースガード
if [[ -n "${_CI_FIX_ESCALATION_SH_SOURCED:-}" ]]; then
    return 0
fi
_CI_FIX_ESCALATION_SH_SOURCED="true"

__CI_FIX_ESCALATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$__CI_FIX_ESCALATION_DIR/log.sh"
source "$__CI_FIX_ESCALATION_DIR/github.sh"

# PRをDraft化して手動対応にエスカレート
# Usage: escalate_to_manual <pr_number> <failure_log>
escalate_to_manual() {
    local pr_number="$1"
    local failure_log="${2:-}"
    
    log_warn "Escalating to manual handling for PR #$pr_number"
    
    # PRをDraft化
    mark_pr_as_draft "$pr_number"
    
    # 失敗ログをコメント追加（要約版）
    local comment="## 🤖 CI自動修正: エスカレーション\n\n"
    comment+="CI失敗の自動修正が困難なため、手動対応が必要です。\n\n"
    comment+="### 失敗サマリー\n"
    comment+="\`\`\`\n"
    # ログの先頭500文字のみ追加
    comment+="$(echo "$failure_log" | head -c 500)"
    comment+="\n\`\`\`\n\n"
    comment+="### 対応が必要な項目\n"
    comment+="- [ ] 失敗ログの確認\n"
    comment+="- [ ] 問題の修正\n"
    comment+="- [ ] CIの再実行\n"
    
    add_pr_comment "$pr_number" "$comment"
    
    return 0
}

# PRをDraft化
# Usage: mark_pr_as_draft <pr_number>
mark_pr_as_draft() {
    local pr_number="$1"
    
    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found. Cannot mark PR as draft."
        return 1
    fi
    
    log_info "Marking PR #$pr_number as draft"
    
    # PRをDraft化（gh CLIのバージョンによって方法が異なる）
    if gh pr ready "$pr_number" --undo 2>/dev/null; then
        log_info "PR marked as draft"
        return 0
    else
        # 代替方法: PRを編集してDraftに
        log_warn "Could not mark PR as draft (may require different gh CLI version)"
        return 1
    fi
}

# PRにコメント追加
# Usage: add_pr_comment <pr_number> <comment>
add_pr_comment() {
    local pr_number="$1"
    local comment="$2"
    
    if ! command -v gh &> /dev/null; then
        log_warn "gh CLI not found. Cannot add comment."
        return 1
    fi
    
    log_info "Adding comment to PR #$pr_number"
    
    if echo "$comment" | gh pr comment "$pr_number" -F - 2>/dev/null; then
        log_info "Comment added successfully"
        return 0
    else
        log_warn "Failed to add comment"
        return 1
    fi
}
