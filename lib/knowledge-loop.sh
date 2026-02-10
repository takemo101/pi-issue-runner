#!/usr/bin/env bash
# ============================================================================
# knowledge-loop.sh - Knowledge Loop: Extract constraints from fix commits
#
# Analyzes fix: commits and docs/decisions/ to extract constraints and lessons,
# then proposes additions to AGENTS.md's "既知の制約" section.
#
# Provides:
#   - extract_fix_commits: Extract fix: commits within a time range
#   - extract_new_decisions: Find recently added decision files
#   - extract_tracker_failures: Analyze failure patterns from tracker.jsonl
#   - check_agents_duplicates: Check if a constraint is already in AGENTS.md
#   - generate_knowledge_proposals: Generate proposal text
#   - apply_knowledge_proposals: Append proposals to AGENTS.md
#   - collect_knowledge_context: Collect knowledge for review context injection
# ============================================================================

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_KNOWLEDGE_LOOP_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_SH_SOURCED="true"

_KNOWLEDGE_LOOP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリの読み込み（未読み込みの場合のみ）
if ! declare -f log_info &>/dev/null; then
    source "$_KNOWLEDGE_LOOP_LIB_DIR/log.sh"
fi

if ! declare -f get_config &>/dev/null; then
    source "$_KNOWLEDGE_LOOP_LIB_DIR/config.sh"
fi

# ============================================================================
# Fix commit extraction
# ============================================================================

# Extract fix: commits within a time range
# Arguments: $1=since (git date string, e.g. "1 week ago"), $2=project_root (optional)
# Output: One line per commit: "<hash> <subject>"
extract_fix_commits() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"

    if ! git -C "$project_root" rev-parse --git-dir &>/dev/null; then
        return 0
    fi

    git -C "$project_root" log \
        --grep="^fix:" \
        --since="$since" \
        --format="%h %s" \
        --no-merges 2>/dev/null || true
}

# Get commit message body (full, not just subject)
# Arguments: $1=commit_hash, $2=project_root (optional)
# Output: commit body text
get_commit_body() {
    local commit_hash="$1"
    local project_root="${2:-.}"

    git -C "$project_root" log -1 --format="%b" "$commit_hash" 2>/dev/null || true
}

# ============================================================================
# Decision file extraction
# ============================================================================

# Extract recently added decision files
# Arguments: $1=since (git date string), $2=project_root (optional)
# Output: One line per file: "<hash> <filepath>"
extract_new_decisions() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"

    if ! git -C "$project_root" rev-parse --git-dir &>/dev/null; then
        return 0
    fi

    # Find commits that added files in docs/decisions/
    git -C "$project_root" log \
        --since="$since" \
        --diff-filter=A \
        --format="%h" \
        --no-merges \
        -- "docs/decisions/*.md" 2>/dev/null | while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        # Get the added file paths
        local files
        files="$(git -C "$project_root" diff-tree --no-commit-id -r --diff-filter=A --name-only "$hash" -- "docs/decisions/*.md" 2>/dev/null)" || continue
        while IFS= read -r filepath; do
            [[ -z "$filepath" ]] && continue
            # Skip README.md
            [[ "$filepath" == "docs/decisions/README.md" ]] && continue
            printf '%s %s\n' "$hash" "$filepath"
        done <<< "$files"
    done
}

# Get decision file title (first heading)
# Arguments: $1=filepath, $2=project_root (optional)
# Output: title text
get_decision_title() {
    local filepath="$1"
    local project_root="${2:-.}"
    local full_path="$project_root/$filepath"

    if [[ ! -f "$full_path" ]]; then
        return 0
    fi

    grep -m1 '^#' "$full_path" 2>/dev/null | sed 's/^#* *//' || true
}

# ============================================================================
# Tracker failure analysis (optional, depends on #1298)
# ============================================================================

# Extract failure patterns from tracker.jsonl
# Arguments: $1=since (git date string), $2=project_root (optional)
# Output: One line per failure pattern: "<count> <error_type>"
extract_tracker_failures() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"

    # Find tracker file
    local tracker_file=""
    local status_dir="$project_root/.worktrees/.status"
    if [[ -f "$status_dir/tracker.jsonl" ]]; then
        tracker_file="$status_dir/tracker.jsonl"
    fi

    if [[ -z "$tracker_file" || ! -f "$tracker_file" ]]; then
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        return 0
    fi

    # Count error_type occurrences
    jq -r 'select(.result == "error") | .error_type // "unknown"' "$tracker_file" 2>/dev/null \
        | sort | uniq -c | sort -rn || true
}

# ============================================================================
# AGENTS.md duplicate checking
# ============================================================================

# Check if a constraint text is already present in AGENTS.md
# Arguments: $1=constraint_text, $2=agents_file (optional, default AGENTS.md)
# Returns: 0 if duplicate found, 1 if not found
check_agents_duplicate() {
    local constraint_text="$1"
    local agents_file="${2:-AGENTS.md}"

    if [[ ! -f "$agents_file" ]]; then
        return 1
    fi

    # Extract keywords from constraint text (at least 3 chars, take first 5 words)
    local keywords
    keywords="$(printf '%s' "$constraint_text" | tr -cs '[:alnum:]' '\n' | awk 'length >= 3' | head -5)"

    if [[ -z "$keywords" ]]; then
        return 1
    fi

    # Check if any keyword appears in the 既知の制約 section
    local constraints_section
    constraints_section="$(sed -n '/## 既知の制約/,/^## /p' "$agents_file" 2>/dev/null)" || constraints_section=""

    if [[ -z "$constraints_section" ]]; then
        return 1
    fi

    local keyword match_count=0
    while IFS= read -r keyword; do
        [[ -z "$keyword" ]] && continue
        if printf '%s' "$constraints_section" | grep -qi "$keyword" 2>/dev/null; then
            match_count=$((match_count + 1))
        fi
    done <<< "$keywords"

    # If more than half of keywords match, consider it a duplicate
    local keyword_count
    keyword_count="$(printf '%s\n' "$keywords" | wc -l | tr -d ' ')"
    if [[ "$keyword_count" -gt 0 ]] && [[ "$match_count" -gt $((keyword_count / 2)) ]]; then
        return 0
    fi

    return 1
}

# ============================================================================
# Proposal generation
# ============================================================================

# Generate knowledge proposals from fix commits and decisions
# Arguments: $1=since (git date string), $2=project_root (optional)
# Output: Formatted proposal text to stdout
generate_knowledge_proposals() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"
    local agents_file="$project_root/AGENTS.md"

    local proposal_count=0
    local proposals=""

    # 1. Extract from fix commits
    local fix_commits
    fix_commits="$(extract_fix_commits "$since" "$project_root")"

    if [[ -n "$fix_commits" ]]; then
        local commit_count
        commit_count="$(printf '%s\n' "$fix_commits" | wc -l | tr -d ' ')"
        log_debug "Found $commit_count fix commits"

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local hash subject
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            subject="$(printf '%s' "$line" | cut -d' ' -f2-)"

            # Strip "fix: " prefix for constraint text
            local constraint
            constraint="$(printf '%s' "$subject" | sed 's/^fix: *//')"

            # Check for duplicates in AGENTS.md
            if check_agents_duplicate "$constraint" "$agents_file"; then
                log_debug "Skipping duplicate: $constraint"
                continue
            fi

            proposal_count=$((proposal_count + 1))

            # Get commit body for additional context
            local body
            body="$(get_commit_body "$hash" "$project_root")"

            proposals+="
${proposal_count}. ${constraint}
   Source: fix: ${subject} (${hash})
"
            if [[ -n "$body" ]]; then
                # Take first non-empty line of body as reason
                local reason
                reason="$(printf '%s' "$body" | grep -v '^$' | head -1)"
                if [[ -n "$reason" ]]; then
                    proposals+="   Reason: ${reason}
"
                fi
            fi
        done <<< "$fix_commits"
    fi

    # 2. Extract from new decision files
    local new_decisions
    new_decisions="$(extract_new_decisions "$since" "$project_root")"

    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local hash filepath
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            filepath="$(printf '%s' "$line" | cut -d' ' -f2-)"

            local title
            title="$(get_decision_title "$filepath" "$project_root")"
            if [[ -z "$title" ]]; then
                title="$filepath"
            fi

            # Check for duplicates
            if check_agents_duplicate "$title" "$agents_file"; then
                log_debug "Skipping duplicate decision: $title"
                continue
            fi

            proposal_count=$((proposal_count + 1))
            proposals+="
${proposal_count}. ${title}
   Source: ${filepath} (${hash})
   Detail: See ${filepath}
"
        done <<< "$new_decisions"
    fi

    # 3. Check tracker failures (optional)
    local tracker_failures
    tracker_failures="$(extract_tracker_failures "$since" "$project_root")"

    if [[ -n "$tracker_failures" ]]; then
        local has_tracker_header=false
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local count error_type
            count="$(printf '%s' "$line" | awk '{print $1}')"
            error_type="$(printf '%s' "$line" | awk '{print $2}')"

            # Only report frequent failures (3+ occurrences)
            if [[ "$count" -ge 3 ]]; then
                if [[ "$has_tracker_header" == "false" ]]; then
                    has_tracker_header=true
                fi
                proposal_count=$((proposal_count + 1))
                proposals+="
${proposal_count}. [failure pattern] ${error_type} occurred ${count} times
   Source: tracker.jsonl analysis
   Action: Consider adding error handling or documentation
"
            fi
        done <<< "$tracker_failures"
    fi

    # Output report
    printf '=== Knowledge Loop Analysis (since: %s) ===\n' "$since"
    printf '\n'

    if [[ "$proposal_count" -eq 0 ]]; then
        printf 'No new constraints found.\n'
        return 0
    fi

    local fix_count=0
    if [[ -n "$fix_commits" ]]; then
        fix_count="$(printf '%s\n' "$fix_commits" | wc -l | tr -d ' ')"
    fi

    printf 'Found %d new constraint(s) from %d fix commit(s):\n' "$proposal_count" "$fix_count"
    printf '%s\n' "$proposals"

    # Generate suggested AGENTS.md additions
    printf 'Suggested AGENTS.md additions (既知の制約 section):\n'
    # Re-parse proposals to generate one-liner additions
    local idx=0
    if [[ -n "$fix_commits" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local hash subject
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            subject="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local constraint
            constraint="$(printf '%s' "$subject" | sed 's/^fix: *//')"
            if check_agents_duplicate "$constraint" "$agents_file"; then
                continue
            fi
            idx=$((idx + 1))
            printf '  - %s (from commit %s)\n' "$constraint" "$hash"
        done <<< "$fix_commits"
    fi

    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
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
            # shellcheck disable=SC2016
            printf '  - %s -> [詳細](%s)\n' "$title" "$filepath"
        done <<< "$new_decisions"
    fi
}

# ============================================================================
# Apply proposals to AGENTS.md
# ============================================================================

# Append knowledge proposals to AGENTS.md's 既知の制約 section
# Arguments: $1=since, $2=project_root (optional)
# Returns: 0=applied, 1=nothing to apply, 2=AGENTS.md not found
apply_knowledge_proposals() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"
    local agents_file="$project_root/AGENTS.md"

    if [[ ! -f "$agents_file" ]]; then
        log_error "AGENTS.md not found at: $agents_file"
        return 2
    fi

    # Collect entries to add
    local entries=""
    local entry_count=0

    # From fix commits
    local fix_commits
    fix_commits="$(extract_fix_commits "$since" "$project_root")"

    if [[ -n "$fix_commits" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local hash subject
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            subject="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local constraint
            constraint="$(printf '%s' "$subject" | sed 's/^fix: *//')"
            if check_agents_duplicate "$constraint" "$agents_file"; then
                continue
            fi
            entry_count=$((entry_count + 1))
            entries+="- ${constraint} (${hash})
"
        done <<< "$fix_commits"
    fi

    # From decision files
    local new_decisions
    new_decisions="$(extract_new_decisions "$since" "$project_root")"

    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
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
            # Use printf to avoid issues with special chars in title
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

# ============================================================================
# Context collection for improve.sh integration
# ============================================================================

# Collect knowledge context for review phase injection
# Arguments: $1=since (git date string), $2=project_root (optional)
# Output: Context string suitable for injection into review prompt
collect_knowledge_context() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"

    local context=""

    # Recent fix commits
    local fix_commits
    fix_commits="$(extract_fix_commits "$since" "$project_root")"

    if [[ -n "$fix_commits" ]]; then
        context+="
## 最近のfix commitから抽出された知見
以下のバグ修正から得られた知見です。同様のパターンのバグがないか確認してください。
\`\`\`
${fix_commits}
\`\`\`
"
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
