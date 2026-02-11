#!/usr/bin/env bash
# ============================================================================
# knowledge-loop/context.sh - Context collection for improve.sh integration
#
# Provides:
#   - collect_knowledge_context: Collect knowledge for review context injection
# ============================================================================

set -euo pipefail

# ソースガード
if [[ -n "${_KNOWLEDGE_LOOP_CONTEXT_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_CONTEXT_SH_SOURCED="true"

_KL_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存サブモジュールの読み込み
if ! declare -f group_commits_by_category &>/dev/null; then
    source "$_KL_CONTEXT_DIR/commits.sh"
fi

if ! declare -f extract_new_decisions &>/dev/null; then
    source "$_KL_CONTEXT_DIR/decisions.sh"
fi

if ! declare -f extract_tracker_failures &>/dev/null; then
    source "$_KL_CONTEXT_DIR/tracker.sh"
fi

# Collect knowledge context for review phase injection
# Uses grouped/scored output for higher quality context
# Arguments: $1=since (git date string), $2=project_root (optional)
# Output: Context string suitable for injection into review prompt
collect_knowledge_context() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"

    local context=""

    # Use grouped data for structured context (top 5 categories)
    local grouped_data
    grouped_data="$(group_commits_by_category "$since" "$project_root")"

    if [[ -n "$grouped_data" ]]; then
        local group_summaries=""
        local group_idx=0
        local current_category="" current_count="" current_files=""
        local -a current_commits=()
        local in_group=false

        _context_flush_group() {
            if [[ "$in_group" != "true" ]] || [[ -z "$current_category" ]]; then
                return
            fi
            if [[ "$group_idx" -ge 5 ]]; then
                return
            fi
            group_idx=$((group_idx + 1))

            group_summaries+="  - [${current_category}] ${current_count}件の修正"
            if [[ -n "$current_files" ]]; then
                group_summaries+=" (${current_files})"
            fi
            group_summaries+=$'\n'

            # Show first 3 commits as examples
            local shown=0
            local c
            for c in "${current_commits[@]}"; do
                if [[ "$shown" -ge 3 ]]; then
                    break
                fi
                local c_subject="${c#*:}"
                group_summaries+="    - ${c_subject}"
                group_summaries+=$'\n'
                shown=$((shown + 1))
            done
        }

        while IFS= read -r line; do
            case "$line" in
                CATEGORY:*)
                    _context_flush_group
                    current_category="${line#CATEGORY:}"
                    current_count=""
                    current_files=""
                    current_commits=()
                    in_group=true
                    ;;
                COUNT:*) current_count="${line#COUNT:}" ;;
                FILES:*) current_files="${line#FILES:}" ;;
                COMMITS:*) current_commits+=("${line#COMMITS:}") ;;
                *) ;;
            esac
        done <<< "$grouped_data"
        _context_flush_group

        if [[ -n "$group_summaries" ]]; then
            context+="
## 最近のfix commitから抽出された知見（上位カテゴリ）
以下のバグ修正パターンが検出されました。同様のバグがないか確認してください。
${group_summaries}
"
        fi
    fi

    # Recent decision files
    local new_decisions
    new_decisions="$(extract_new_decisions "$since" "$project_root")"

    if [[ -n "$new_decisions" ]]; then
        local decision_summaries=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local filepath
            filepath="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local title
            title="$(get_decision_title "$filepath" "$project_root")"
            if [[ -n "$title" ]]; then
                decision_summaries+="  - ${title} (${filepath})
"
            fi
        done <<< "$new_decisions"

        if [[ -n "$decision_summaries" ]]; then
            context+="
## 最近追加された設計判断
以下の制約を考慮してレビューしてください。
${decision_summaries}
"
        fi
    fi

    # Tracker failure patterns (optional)
    local tracker_failures
    tracker_failures="$(extract_tracker_failures "$since" "$project_root")"

    if [[ -n "$tracker_failures" ]]; then
        local significant_failures=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local count
            count="$(printf '%s' "$line" | awk '{print $1}')"
            if [[ "$count" -ge 2 ]]; then
                significant_failures+="  ${line}
"
            fi
        done <<< "$tracker_failures"

        if [[ -n "$significant_failures" ]]; then
            context+="
## 繰り返し発生している失敗パターン
以下のエラータイプが繰り返し発生しています。関連するコードを重点的に確認してください。
\`\`\`
${significant_failures}
\`\`\`
"
        fi
    fi

    printf '%s' "$context"
}
