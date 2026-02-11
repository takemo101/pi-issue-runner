#!/usr/bin/env bash
# ============================================================================
# knowledge-loop/commits.sh - Fix commit extraction, categorization, and grouping
#
# Provides:
#   - extract_fix_commits: Extract fix: commits within a time range
#   - get_commit_body: Get commit message body
#   - categorize_commit: Categorize a commit based on changed files
#   - score_commit: Score a commit for importance
#   - group_commits_by_category: Group commits by category and aggregate
# ============================================================================

set -euo pipefail

# ソースガード
if [[ -n "${_KNOWLEDGE_LOOP_COMMITS_SH_SOURCED:-}" ]]; then
    return 0
fi
_KNOWLEDGE_LOOP_COMMITS_SH_SOURCED="true"

_KL_COMMITS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KL_COMMITS_LIB_DIR="$(cd "$_KL_COMMITS_DIR/.." && pwd)"

# 依存ライブラリの読み込み（未読み込みの場合のみ）
if ! declare -f log_info &>/dev/null; then
    source "$_KL_COMMITS_LIB_DIR/log.sh"
fi

if ! declare -f get_config &>/dev/null; then
    source "$_KL_COMMITS_LIB_DIR/config.sh"
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

    # Lazy-load tracker module for check_agents_duplicate
    if ! declare -f check_agents_duplicate &>/dev/null; then
        source "$_KL_COMMITS_DIR/tracker.sh"
    fi

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
