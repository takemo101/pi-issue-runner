#!/usr/bin/env bash
# ============================================================================
# knowledge-loop/tracker.sh - Tracker failure analysis and AGENTS.md utilities
#
# Provides:
#   - extract_tracker_failures: Analyze failure patterns from tracker.jsonl
#   - check_agents_duplicate: Check if a constraint is already in AGENTS.md
#   - _score_to_stars: Convert numeric score to star rating
# ============================================================================

set -euo pipefail

# ソースガード
if [[ -n "${_KNOWLEDGE_LOOP_TRACKER_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_TRACKER_SH_SOURCED="true"

# Extract failure patterns from tracker.jsonl
# Arguments: $1=since (git date string), $2=project_root (optional)
# Output: One line per failure pattern: "<count> <error_type>"
extract_tracker_failures() {
    # shellcheck disable=SC2034  # since is reserved for future time-based filtering
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
