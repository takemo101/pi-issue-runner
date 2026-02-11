#!/usr/bin/env bash
# ============================================================================
# knowledge-loop/proposals.sh - Proposal generation and application
#
# Provides:
#   - generate_knowledge_proposals: Generate proposal text from fix commits/decisions
#   - apply_knowledge_proposals: Append proposals to AGENTS.md
# ============================================================================

set -euo pipefail

# ソースガード
if [[ -n "${_KNOWLEDGE_LOOP_PROPOSALS_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_PROPOSALS_SH_SOURCED="true"

_KL_PROPOSALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KL_PROPOSALS_LIB_DIR="$(cd "$_KL_PROPOSALS_DIR/.." && pwd)"

# 依存ライブラリの読み込み（未読み込みの場合のみ）
if ! declare -f log_info &>/dev/null; then
    source "$_KL_PROPOSALS_LIB_DIR/log.sh"
fi

# 依存サブモジュールの読み込み
if ! declare -f extract_fix_commits &>/dev/null; then
    source "$_KL_PROPOSALS_DIR/commits.sh"
fi

if ! declare -f extract_new_decisions &>/dev/null; then
    source "$_KL_PROPOSALS_DIR/decisions.sh"
fi

if ! declare -f check_agents_duplicate &>/dev/null; then
    source "$_KL_PROPOSALS_DIR/tracker.sh"
fi

# ============================================================================
# Proposal generation
# ============================================================================

# Generate knowledge proposals from fix commits and decisions
# Arguments: $1=since, $2=project_root (optional), $3=top_n (optional, 0=all)
# Output: Formatted proposal text to stdout
generate_knowledge_proposals() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"
    local top_n="${3:-5}"
    local agents_file="$project_root/AGENTS.md"

    # Count total fix commits (before filtering)
    local fix_commits
    fix_commits="$(extract_fix_commits "$since" "$project_root")"
    local total_fix_count=0
    if [[ -n "$fix_commits" ]]; then
        total_fix_count="$(printf '%s\n' "$fix_commits" | wc -l | tr -d ' ')"
    fi

    # Get grouped data
    local grouped_data
    grouped_data="$(group_commits_by_category "$since" "$project_root")"

    # Count decision proposals
    local new_decisions
    new_decisions="$(extract_new_decisions "$since" "$project_root")"
    local decision_count=0
    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local _hash filepath
            _hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            filepath="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local title
            title="$(get_decision_title "$filepath" "$project_root")"
            if [[ -z "$title" ]]; then
                title="$filepath"
            fi
            if ! check_agents_duplicate "$title" "$agents_file"; then
                decision_count=$((decision_count + 1))
            fi
        done <<< "$new_decisions"
    fi

    # Output report header
    printf '=== Knowledge Loop Analysis (since: %s) ===\n' "$since"
    printf '\n'

    # Count total groups
    local group_count=0
    if [[ -n "$grouped_data" ]]; then
        group_count="$(printf '%s\n' "$grouped_data" | grep -c '^CATEGORY:' || true)"
    fi

    local total_insights=$((group_count + decision_count))

    if [[ "$total_insights" -eq 0 ]]; then
        printf 'No new constraints found.\n'
        return 0
    fi

    # Determine display count
    local display_count="$total_insights"
    if [[ "$top_n" -gt 0 ]] && [[ "$top_n" -lt "$total_insights" ]]; then
        display_count="$top_n"
    fi

    printf 'Top %d insights (from %d fix commits):\n' "$display_count" "$total_fix_count"
    printf '\n'

    # Display grouped commit insights
    local displayed=0
    if [[ -n "$grouped_data" ]]; then
        local current_category="" current_count="" current_score="" current_files=""
        local -a current_commits=()
        local in_group=false

        _flush_group() {
            if [[ "$in_group" != "true" ]] || [[ -z "$current_category" ]]; then
                return
            fi
            if [[ "$top_n" -gt 0 ]] && [[ "$displayed" -ge "$top_n" ]]; then
                return
            fi

            displayed=$((displayed + 1))
            local stars
            stars="$(_score_to_stars "$current_score")"
            printf '%d. [%s] %s (%d fixes)\n' "$displayed" "$current_category" "$stars" "$current_count"

            # Show up to 5 commits
            local shown=0
            local commit_line
            for commit_line in "${current_commits[@]}"; do
                if [[ "$shown" -ge 5 ]]; then
                    local remaining=$(( ${#current_commits[@]} - 5 ))
                    printf '   ... and %d more\n' "$remaining"
                    break
                fi
                local c_hash c_subject
                c_hash="${commit_line%%:*}"
                c_subject="${commit_line#*:}"
                printf '   - %s (%s)\n' "$c_subject" "$c_hash"
                shown=$((shown + 1))
            done

            if [[ -n "$current_files" ]]; then
                printf '   Files: %s\n' "$current_files"
            fi
            printf '\n'
        }

        while IFS= read -r line; do
            case "$line" in
                CATEGORY:*)
                    _flush_group
                    current_category="${line#CATEGORY:}"
                    current_count=""
                    current_score=""
                    current_files=""
                    current_commits=()
                    in_group=true
                    ;;
                COUNT:*)
                    current_count="${line#COUNT:}"
                    ;;
                SCORE:*)
                    current_score="${line#SCORE:}"
                    ;;
                FILES:*)
                    current_files="${line#FILES:}"
                    ;;
                COMMITS:*)
                    current_commits+=("${line#COMMITS:}")
                    ;;
                "")
                    # End of group block - will be flushed on next CATEGORY: or at end
                    ;;
            esac
        done <<< "$grouped_data"

        # Flush last group
        _flush_group
    fi

    # Display decision file proposals (within top_n limit)
    if [[ -n "$new_decisions" ]] && { [[ "$top_n" -eq 0 ]] || [[ "$displayed" -lt "$top_n" ]]; }; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$top_n" -gt 0 ]] && [[ "$displayed" -ge "$top_n" ]]; then
                break
            fi
            local hash filepath
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            filepath="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local title
            title="$(get_decision_title "$filepath" "$project_root")"
            if [[ -z "$title" ]]; then
                title="$filepath"
            fi
            if check_agents_duplicate "$title" "$agents_file"; then
                continue
            fi
            displayed=$((displayed + 1))
            printf '%d. [設計判断] %s\n' "$displayed" "$title"
            printf '   Source: %s (%s)\n' "$filepath" "$hash"
            printf '\n'
        done <<< "$new_decisions"
    fi

    # Show total if limited
    if [[ "$top_n" -gt 0 ]] && [[ "$total_insights" -gt "$display_count" ]]; then
        printf '(Showing top %d of %d insights. Use --all to see all)\n' "$display_count" "$total_insights"
    fi
}

# ============================================================================
# Apply proposals to AGENTS.md
# ============================================================================

# Append knowledge proposals to AGENTS.md's 既知の制約 section
# Uses grouped/scored results to apply only top N entries
# Arguments: $1=since, $2=project_root (optional), $3=top_n (optional, 0=all)
# Returns: 0=applied, 1=nothing to apply, 2=AGENTS.md not found
apply_knowledge_proposals() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"
    local top_n="${3:-5}"
    local agents_file="$project_root/AGENTS.md"

    if [[ ! -f "$agents_file" ]]; then
        log_error "AGENTS.md not found at: $agents_file"
        return 2
    fi

    # Collect entries using grouped data (respects scoring/limiting)
    local entries=""
    local entry_count=0
    local applied_groups=0

    # From grouped fix commits (sorted by score)
    local grouped_data
    grouped_data="$(group_commits_by_category "$since" "$project_root")"

    if [[ -n "$grouped_data" ]]; then
        local current_category="" current_commits_text=""
        local in_group=false

        _apply_flush_group() {
            if [[ "$in_group" != "true" ]] || [[ -z "$current_category" ]]; then
                return
            fi
            if [[ "$top_n" -gt 0 ]] && [[ "$applied_groups" -ge "$top_n" ]]; then
                return
            fi
            applied_groups=$((applied_groups + 1))

            # Add a summary entry per group
            if [[ -n "$current_commits_text" ]]; then
                local first_constraint
                first_constraint="$(printf '%s' "$current_commits_text" | head -1)"
                local c_hash="${first_constraint%%:*}"
                local c_subject="${first_constraint#*:}"
                entry_count=$((entry_count + 1))
                entries+="- ${c_subject} (${c_hash})"
                entries+=$'\n'
            fi
        }

        while IFS= read -r line; do
            case "$line" in
                CATEGORY:*)
                    _apply_flush_group
                    current_category="${line#CATEGORY:}"
                    current_commits_text=""
                    in_group=true
                    ;;
                COMMITS:*)
                    current_commits_text+="${line#COMMITS:}"
                    current_commits_text+=$'\n'
                    ;;
                "") ;;
                *) ;;
            esac
        done <<< "$grouped_data"

        _apply_flush_group
    fi

    # From decision files (within remaining top_n budget)
    local new_decisions
    new_decisions="$(extract_new_decisions "$since" "$project_root")"

    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$top_n" -gt 0 ]] && [[ "$entry_count" -ge "$top_n" ]]; then
                break
            fi
            local hash filepath
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            filepath="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local title
            title="$(get_decision_title "$filepath" "$project_root")"
            if [[ -z "$title" ]]; then
                title="$filepath"
            fi
            if check_agents_duplicate "$title" "$agents_file"; then
                continue
            fi
            entry_count=$((entry_count + 1))
            entries+="$(printf -- '- %s -> [詳細](%s)\n' "$title" "$filepath")"
            entries+=$'\n'
        done <<< "$new_decisions"
    fi

    if [[ "$entry_count" -eq 0 ]]; then
        log_info "No new constraints to add"
        return 1
    fi

    # Find the line number of "## 既知の制約" section
    local section_line
    section_line="$(grep -n '^## 既知の制約' "$agents_file" 2>/dev/null | head -1 | cut -d: -f1)" || section_line=""

    if [[ -z "$section_line" ]]; then
        log_warn "Section '## 既知の制約' not found in AGENTS.md, appending at end"
        printf '\n## 既知の制約\n\n%s' "$entries" >> "$agents_file"
    else
        # Find the next section (## ...) after 既知の制約 or end of file
        local total_lines
        total_lines="$(wc -l < "$agents_file" | tr -d ' ')"
        local next_section_line
        next_section_line="$(tail -n +"$((section_line + 1))" "$agents_file" | grep -n '^## ' | head -1 | cut -d: -f1)" || next_section_line=""

        local insert_line
        if [[ -n "$next_section_line" ]]; then
            # Insert before the next section (adjust for tail offset)
            insert_line=$((section_line + next_section_line - 1))
        else
            # Append at end of file
            insert_line=$((total_lines + 1))
        fi

        # Build the new file content
        local tmp_file="${agents_file}.tmp.$$"
        {
            head -n "$((insert_line - 1))" "$agents_file"
            printf '%s' "$entries"
            tail -n +"$insert_line" "$agents_file"
        } > "$tmp_file"
        mv -f "$tmp_file" "$agents_file"
    fi

    log_info "Applied $entry_count constraint(s) to AGENTS.md"
    return 0
}
