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

# Get diff summary for a commit
# Arguments: $1=commit_hash, $2=project_root (optional)
# Output: diff stat lines
get_commit_diff_summary() {
    local commit_hash="$1"
    local project_root="${2:-.}"

    git -C "$project_root" diff-tree --no-commit-id -r --stat "$commit_hash" 2>/dev/null || true
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
# Commit categorization and grouping
# ============================================================================

# Category definitions: pattern -> category name
# Used by categorize_commit() to classify commits by changed files
_KNOWLEDGE_CATEGORIES=(
    "lib/marker.sh|watch-session.sh:マーカー検出"
    "lib/ci-|ci-fix|ci-classifier|ci-monitor|ci-retry:CI関連"
    "lib/multiplexer|lib/tmux.sh:マルチプレクサ"
    "lib/worktree.sh|scripts/cleanup.sh:Worktree管理"
    "lib/hooks.sh:Hook安全性"
    "lib/workflow|workflow-:ワークフロー"
    "lib/config.sh|lib/yaml.sh:設定・YAML"
    "lib/status.sh|lib/dashboard.sh:状態管理"
    "lib/improve|scripts/improve.sh:継続的改善"
    "lib/daemon.sh:デーモン管理"
    "lib/compat.sh:互換性"
    "lib/notify.sh:通知"
)

# Categorize a commit based on changed files
# Arguments: $1=commit_hash, $2=project_root (optional)
# Output: category name (e.g., "マーカー検出", "CI関連", "一般")
categorize_commit() {
    local commit_hash="$1"
    local project_root="${2:-.}"

    local changed_files
    changed_files="$(git -C "$project_root" diff-tree --no-commit-id -r --name-only "$commit_hash" 2>/dev/null)" || changed_files=""

    if [[ -z "$changed_files" ]]; then
        printf '%s' "一般"
        return 0
    fi

    # Check if only test files changed
    local has_non_test=false
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ "$f" != test/* ]]; then
            has_non_test=true
            break
        fi
    done <<< "$changed_files"

    if [[ "$has_non_test" == "false" ]]; then
        printf '%s' "テスト安定性"
        return 0
    fi

    # Match against category patterns
    local entry pattern category
    for entry in "${_KNOWLEDGE_CATEGORIES[@]}"; do
        pattern="${entry%%:*}"
        category="${entry#*:}"
        # Split pattern by | and check each
        local IFS='|'
        local p
        for p in $pattern; do
            if printf '%s\n' "$changed_files" | grep -q "$p" 2>/dev/null; then
                printf '%s' "$category"
                return 0
            fi
        done
    done

    printf '%s' "一般"
}

# Score a commit for importance
# Arguments: $1=commit_hash, $2=commit_subject, $3=project_root (optional)
# Output: numeric score (higher = more important)
score_commit() {
    local commit_hash="$1"
    local subject="$2"
    local project_root="${3:-.}"
    local score=1

    # Check if commit references an Issue number -> +2
    if printf '%s' "$subject" | grep -qE '#[0-9]+|Issue[ -]?[0-9]+' 2>/dev/null; then
        score=$((score + 2))
    fi

    # Check commit body for Issue references -> +1
    local body
    body="$(get_commit_body "$commit_hash" "$project_root")"
    if [[ -n "$body" ]] && printf '%s' "$body" | grep -qE '#[0-9]+|Refs|Closes|Fixes' 2>/dev/null; then
        score=$((score + 1))
    fi

    local changed_files
    changed_files="$(git -C "$project_root" diff-tree --no-commit-id -r --name-only "$commit_hash" 2>/dev/null)" || changed_files=""

    # Check if only test files changed -> low score
    local has_non_test=false
    if [[ -n "$changed_files" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if [[ "$f" != test/* ]]; then
                has_non_test=true
                break
            fi
        done <<< "$changed_files"
    fi
    if [[ "$has_non_test" == "false" ]]; then
        score=$((score - 1))
    fi

    # Typo/ShellCheck-only fix -> lowest score
    if printf '%s' "$subject" | grep -qiE 'typo|shellcheck|SC[0-9]+|format' 2>/dev/null; then
        score=$((score - 1))
    fi

    # Minimum score is 0
    if [[ "$score" -lt 0 ]]; then
        score=0
    fi

    printf '%d' "$score"
}

# Group commits by category and aggregate
# Arguments: $1=since, $2=project_root (optional)
# Output: grouped data in a parseable format (one group per block, separated by empty lines)
#   Format per group:
#     CATEGORY:<name>
#     COUNT:<n>
#     SCORE:<total_score>
#     FILES:<comma-separated unique files>
#     COMMITS:<hash1>:<subject1>
#     COMMITS:<hash2>:<subject2>
#     ...
group_commits_by_category() {
    local since="${1:-1 week ago}"
    local project_root="${2:-.}"
    local agents_file="$project_root/AGENTS.md"

    local fix_commits
    fix_commits="$(extract_fix_commits "$since" "$project_root")"

    if [[ -z "$fix_commits" ]]; then
        return 0
    fi

    # Use temp files for grouping (associative arrays are fragile in bash)
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local hash subject
        hash="$(printf '%s' "$line" | cut -d' ' -f1)"
        subject="$(printf '%s' "$line" | cut -d' ' -f2-)"

        local constraint
        constraint="$(printf '%s' "$subject" | sed 's/^fix: *//')"

        # Skip duplicates already in AGENTS.md
        if check_agents_duplicate "$constraint" "$agents_file"; then
            continue
        fi

        local category
        category="$(categorize_commit "$hash" "$project_root")"

        # Sanitize category for filename (cksum is POSIX, handles multibyte)
        local cat_file
        cat_file="cat_$(printf '%s' "$category" | cksum | cut -d' ' -f1)"

        # Store category name
        printf '%s\n' "$category" > "$tmp_dir/${cat_file}.name"

        # Append commit
        printf '%s:%s\n' "$hash" "$constraint" >> "$tmp_dir/${cat_file}.commits"

        # Append score
        local commit_score
        commit_score="$(score_commit "$hash" "$subject" "$project_root")"
        printf '%d\n' "$commit_score" >> "$tmp_dir/${cat_file}.scores"

        # Append changed files
        local changed_files
        changed_files="$(git -C "$project_root" diff-tree --no-commit-id -r --name-only "$hash" 2>/dev/null)" || changed_files=""
        if [[ -n "$changed_files" ]]; then
            printf '%s\n' "$changed_files" >> "$tmp_dir/${cat_file}.files"
        fi
    done <<< "$fix_commits"

    # Output grouped data, sorted by total score descending
    local scored_groups=""
    for name_file in "$tmp_dir"/*.name; do
        [[ -f "$name_file" ]] || continue
        local base
        base="$(basename "$name_file" .name)"
        local cat_name
        cat_name="$(cat "$name_file")"
        local commit_count=0
        local total_score=0

        if [[ -f "$tmp_dir/${base}.commits" ]]; then
            commit_count="$(wc -l < "$tmp_dir/${base}.commits" | tr -d ' ')"
        fi

        # Total score = sum of individual scores + bonus for repeated fixes
        if [[ -f "$tmp_dir/${base}.scores" ]]; then
            while IFS= read -r s; do
                total_score=$((total_score + s))
            done < "$tmp_dir/${base}.scores"
        fi

        # Bonus: repeated fixes on same category -> higher score
        if [[ "$commit_count" -ge 5 ]]; then
            total_score=$((total_score + 5))
        elif [[ "$commit_count" -ge 3 ]]; then
            total_score=$((total_score + 3))
        elif [[ "$commit_count" -ge 2 ]]; then
            total_score=$((total_score + 1))
        fi

        # Count unique files modified
        local unique_files=""
        if [[ -f "$tmp_dir/${base}.files" ]]; then
            unique_files="$(sort -u "$tmp_dir/${base}.files" | head -5 | tr '\n' ',' | sed 's/,$//')"
        fi

        scored_groups+="$(printf '%05d\t%s\t%s\t%s\t%s\n' "$total_score" "$cat_name" "$commit_count" "$unique_files" "$base")"
        scored_groups+=$'\n'
    done

    # Sort by score descending and output
    if [[ -z "$scored_groups" ]]; then
        rm -rf "$tmp_dir"
        return 0
    fi

    printf '%s' "$scored_groups" | sort -t$'\t' -k1 -rn | while IFS=$'\t' read -r _score cat_name commit_count unique_files base; do
        [[ -z "$cat_name" ]] && continue
        printf 'CATEGORY:%s\n' "$cat_name"
        printf 'COUNT:%s\n' "$commit_count"
        printf 'SCORE:%d\n' "$(( ${_score#0} ))"  # Strip leading zeros
        printf 'FILES:%s\n' "$unique_files"
        if [[ -f "$tmp_dir/${base}.commits" ]]; then
            while IFS= read -r commit_line; do
                printf 'COMMITS:%s\n' "$commit_line"
            done < "$tmp_dir/${base}.commits"
        fi
        printf '\n'
    done

    rm -rf "$tmp_dir"
}

# Convert a numeric score to a star rating
# Arguments: $1=score, $2=max_score (optional, for normalization)
# Output: star string (e.g., "★★★", "★★☆", "★☆☆")
_score_to_stars() {
    local score="$1"
    if [[ "$score" -ge 10 ]]; then
        printf '★★★'
    elif [[ "$score" -ge 5 ]]; then
        printf '★★☆'
    elif [[ "$score" -ge 2 ]]; then
        printf '★☆☆'
    else
        printf '☆☆☆'
    fi
}

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

# ============================================================================
# Context collection for improve.sh integration
# ============================================================================

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
