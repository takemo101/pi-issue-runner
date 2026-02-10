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
    --apply              Apply proposals to AGENTS.md
    --dry-run            Show proposals only (default)
    --json               Output in JSON format
    -h, --help           Show this help

Description:
    Extracts constraints and lessons from recent fix: commits and
    docs/decisions/ files, then proposes additions to the AGENTS.md
    "既知の制約" section.

    Sources analyzed:
    1. fix: commits (git log --grep="^fix:")
    2. New docs/decisions/*.md files
    3. tracker.jsonl failure patterns (if available)

Examples:
    knowledge-loop.sh                         # Analyze last 7 days
    knowledge-loop.sh --since "1 week ago"    # Same as above
    knowledge-loop.sh --since "3 days ago"    # Last 3 days only
    knowledge-loop.sh --apply                 # Apply to AGENTS.md
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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)
                since="$2"
                shift 2
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
                echo "Usage: $(basename "$0") [--since PERIOD] [--apply] [--dry-run] [--json] [-h]" >&2
                exit 1
                ;;
        esac
    done

    load_config 2>/dev/null || true

    if [[ "$json_output" == "true" ]]; then
        _output_json "$since"
        return 0
    fi

    case "$mode" in
        dry-run)
            generate_knowledge_proposals "$since" "."
            ;;
        apply)
            generate_knowledge_proposals "$since" "."
            echo ""
            echo "Applying proposals to AGENTS.md..."
            local apply_result=0
            apply_knowledge_proposals "$since" "." || apply_result=$?
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

    local fix_commits
    fix_commits="$(extract_fix_commits "$since" ".")"

    local new_decisions
    new_decisions="$(extract_new_decisions "$since" ".")"

    if ! command -v jq &>/dev/null; then
        log_error "jq is required for --json output"
        exit 1
    fi

    local items="[]"

    if [[ -n "$fix_commits" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local hash subject
            hash="$(printf '%s' "$line" | cut -d' ' -f1)"
            subject="$(printf '%s' "$line" | cut -d' ' -f2-)"
            local constraint
            constraint="$(printf '%s' "$subject" | sed 's/^fix: *//')"
            if check_agents_duplicate "$constraint" "AGENTS.md"; then
                continue
            fi
            items="$(printf '%s' "$items" | jq -c --arg type "fix_commit" --arg hash "$hash" --arg subject "$subject" --arg constraint "$constraint" '. + [{type: $type, hash: $hash, subject: $subject, constraint: $constraint}]')"
        done <<< "$fix_commits"
    fi

    if [[ -n "$new_decisions" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
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
