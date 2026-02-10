#!/usr/bin/env bash
# ============================================================================
# knowledge-loop.sh - Knowledge Loop CLI
#
# Extracts constraints from fix commits and docs/decisions/,
# then proposes (or applies) additions to AGENTS.md.
#
# Usage: ./scripts/knowledge-loop.sh [options]
#
# Options:
#   --since "N days ago"  Period to analyze (default: "1 week ago")
#   --top N               Show top N insights (default: 5)
#   --all                 Show all insights (no limit)
#   --apply               Apply proposals to AGENTS.md
#   --dry-run             Show proposals only (default)
#   --json                Output in JSON format
#   -h, --help            Show help message
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - AGENTS.md not found (with --apply)
#
# Examples:
#   ./scripts/knowledge-loop.sh
#   ./scripts/knowledge-loop.sh --since "1 week ago"
#   ./scripts/knowledge-loop.sh --top 10
#   ./scripts/knowledge-loop.sh --all
#   ./scripts/knowledge-loop.sh --apply
#   ./scripts/knowledge-loop.sh --dry-run
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
Usage: knowledge-loop.sh [options]

Options:
    --since "PERIOD"     Period to analyze (default: "1 week ago")
                         Examples: "1 week ago", "3 days ago", "1 month ago"
    --top N              Show top N insights (default: 5)
    --all                Show all insights (no limit)
    --apply              Apply top N proposals to AGENTS.md
    --dry-run            Show proposals only (default)
    --json               Output in JSON format
    -h, --help           Show this help

Description:
    Extracts constraints and lessons from recent fix: commits and
    docs/decisions/ files, groups them by category, scores by importance,
    and proposes additions to the AGENTS.md "既知の制約" section.

    Categories are auto-detected from changed file paths:
    - lib/marker.sh, watch-session.sh → マーカー検出
    - lib/ci-*.sh → CI関連
    - test/ only → テスト安定性
    - lib/multiplexer*.sh → マルチプレクサ
    - lib/worktree.sh → Worktree管理

    Scoring is based on:
    - Number of repeated fixes in the same category (highest weight)
    - Issue number references in commits
    - Test-only vs production code changes
    - Typo/ShellCheck fixes (lowest weight)

    Sources analyzed:
    1. fix: commits (git log --grep="^fix:")
    2. New docs/decisions/*.md files
    3. tracker.jsonl failure patterns (if available)

Examples:
    knowledge-loop.sh                         # Top 5 insights from last 7 days
    knowledge-loop.sh --since "1 month ago"   # Top 5 from last month
    knowledge-loop.sh --top 10                # Top 10 insights
    knowledge-loop.sh --all                   # All insights (no limit)
    knowledge-loop.sh --apply                 # Apply top 5 to AGENTS.md
    knowledge-loop.sh --apply --top 3         # Apply top 3 to AGENTS.md
    knowledge-loop.sh --dry-run               # Preview only (default)
EOF
        exit 0
    fi
done

source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/knowledge-loop.sh"

main() {
    local since="1 week ago"
    local mode="dry-run"
    local json_output=false
    local top_n=5

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)
                since="$2"
                shift 2
                ;;
            --top)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--top requires a positive integer argument"
                    exit 1
                fi
                top_n="$2"
                shift 2
                ;;
            --all)
                top_n=0
                shift
                ;;
            --apply)
                mode="apply"
                shift
                ;;
            --dry-run)
                mode="dry-run"
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            -h|--help)
                # Already handled above
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: $(basename "$0") [--since PERIOD] [--top N] [--all] [--apply] [--dry-run] [--json] [-h]" >&2
                exit 1
                ;;
        esac
    done

    load_config 2>/dev/null || true

    if [[ "$json_output" == "true" ]]; then
        _output_json "$since" "$top_n"
        return 0
    fi

    case "$mode" in
        dry-run)
            generate_knowledge_proposals "$since" "." "$top_n"
            ;;
        apply)
            generate_knowledge_proposals "$since" "." "$top_n"
            echo ""
            echo "Applying proposals to AGENTS.md..."
            local apply_result=0
            apply_knowledge_proposals "$since" "." "$top_n" || apply_result=$?
            case "$apply_result" in
                0) echo "Done. Proposals applied to AGENTS.md." ;;
                1) echo "No new constraints to apply." ;;
                2) echo "Error: AGENTS.md not found." >&2; exit 2 ;;
            esac
            ;;
    esac
}

_output_json() {
    local since="$1"
    local top_n="${2:-5}"

    if ! command -v jq &>/dev/null; then
        log_error "jq is required for --json output"
        exit 1
    fi

    local items="[]"

    # Use grouped data for structured JSON output
    local grouped_data
    grouped_data="$(group_commits_by_category "$since" ".")"

    if [[ -n "$grouped_data" ]]; then
        local current_category="" current_count="" current_score="" current_files=""
        local -a current_commits=()
        local group_idx=0
        local in_group=false

        _json_flush_group() {
            if [[ "$in_group" != "true" ]] || [[ -z "$current_category" ]]; then
                return
            fi
            if [[ "$top_n" -gt 0 ]] && [[ "$group_idx" -ge "$top_n" ]]; then
                return
            fi
            group_idx=$((group_idx + 1))

            # Build commits array
            local commits_json="[]"
            local c
            for c in "${current_commits[@]}"; do
                local c_hash="${c%%:*}"
                local c_subject="${c#*:}"
                commits_json="$(printf '%s' "$commits_json" | jq -c --arg hash "$c_hash" --arg subject "$c_subject" '. + [{hash: $hash, subject: $subject}]')"
            done

            items="$(printf '%s' "$items" | jq -c \
                --arg type "category" \
                --arg category "$current_category" \
                --argjson count "${current_count:-0}" \
                --argjson score "${current_score:-0}" \
                --arg files "${current_files:-}" \
                --argjson commits "$commits_json" \
                '. + [{type: $type, category: $category, count: $count, score: $score, files: $files, commits: $commits}]')"
        }

        while IFS= read -r line; do
            case "$line" in
                CATEGORY:*)
                    _json_flush_group
                    current_category="${line#CATEGORY:}"
                    current_count=""
                    current_score=""
                    current_files=""
                    current_commits=()
                    in_group=true
                    ;;
                COUNT:*) current_count="${line#COUNT:}" ;;
                SCORE:*) current_score="${line#SCORE:}" ;;
                FILES:*) current_files="${line#FILES:}" ;;
                COMMITS:*) current_commits+=("${line#COMMITS:}") ;;
                *) ;;
            esac
        done <<< "$grouped_data"
        _json_flush_group
    fi

    # Decision files
    local new_decisions
    new_decisions="$(extract_new_decisions "$since" ".")"

    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local current_items_count
            current_items_count="$(printf '%s' "$items" | jq 'length')"
            if [[ "$top_n" -gt 0 ]] && [[ "$current_items_count" -ge "$top_n" ]]; then
                break
            fi
            local hash filepath
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            filepath="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local title
            title="$(get_decision_title "$filepath" ".")"
            if [[ -z "$title" ]]; then
                title="$filepath"
            fi
            if check_agents_duplicate "$title" "AGENTS.md"; then
                continue
            fi
            items="$(printf '%s' "$items" | jq -c --arg type "decision" --arg hash "$hash" --arg filepath "$filepath" --arg title "$title" '. + [{type: $type, hash: $hash, filepath: $filepath, title: $title}]')"
        done <<< "$new_decisions"
    fi

    printf '%s\n' "$items" | jq '.'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
