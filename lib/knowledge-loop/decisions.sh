#!/usr/bin/env bash
# ============================================================================
# knowledge-loop/decisions.sh - Decision file extraction
#
# Provides:
#   - extract_new_decisions: Find recently added decision files
#   - get_decision_title: Get decision file title (first heading)
# ============================================================================

set -euo pipefail

# ソースガード
if [[ -n "${_KNOWLEDGE_LOOP_DECISIONS_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_DECISIONS_SH_SOURCED="true"

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
