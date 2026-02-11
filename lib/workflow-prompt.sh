#!/usr/bin/env bash
# ============================================================================
# lib/workflow-prompt.sh - Simple prompt generation for workflows
#
# Responsibilities:
#   - Generate prompts for AI steps with optional context
#   - Handle template variable substitution
# ============================================================================

set -euo pipefail

_WORKFLOW_PROMPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_PROMPT_LIB_DIR/log.sh"
source "$_WORKFLOW_PROMPT_LIB_DIR/workflow-loader.sh"

# ============================================================================
# Prompt Generation
# ============================================================================

# Generate complete prompt for a workflow step
# Usage: generate_step_prompt <step_name> <step_context> <issue_number> <issue_title> <issue_body> <branch_name> <worktree_path> [project_root] [workflow_name]
generate_step_prompt() {
    local step_name="$1"
    local step_context="$2"
    local issue_number="$3"
    local issue_title="$4"
    local issue_body="$5"
    local branch_name="$6"
    local worktree_path="$7"
    local project_root="${8:-.}"
    local workflow_name="${9:-default}"

    # Find agent file
    local agent_file
    agent_file=$(find_agent_file "$step_name" "$project_root")

    # Get base agent prompt
    local base_prompt
    base_prompt=$(get_agent_prompt "$agent_file" "$issue_number" "$branch_name" "$worktree_path" "$step_name" "$issue_title" "" "$workflow_name")

    # Output header
    cat << EOF
# GitHub Issue #${issue_number} - ${step_name}

**Title:** ${issue_title}
**Branch:** ${branch_name}
**Workflow:** ${workflow_name}

EOF

    # Output base prompt
    echo "$base_prompt"

    # Add context if provided
    if [[ -n "$step_context" ]]; then
        cat << EOF

---

## Additional Context for This Step

${step_context}

EOF
    fi

    # Output completion marker instruction
    cat << EOF

---

## Completion

After completing all tasks above, output the completion marker:

\`\`\`
###TASK_COMPLETE_${issue_number}###
\`\`\`

This marker signals that the step is complete and triggers cleanup.
EOF
}

# Find agent file for a step
# Usage: find_agent_file <step_name> [project_root]
find_agent_file() {
    local step_name="$1"
    local project_root="${2:-.}"

    # Check builtin first
    case "$step_name" in
        plan|implement|review|merge|test|ci-fix)
            echo "builtin:$step_name"
            return 0
            ;;
    esac

    # Check project agents directory
    local agent_file="$project_root/agents/${step_name}.md"
    if [[ -f "$agent_file" ]]; then
        echo "$agent_file"
        return 0
    fi

    # Check builtin agents directory
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    agent_file="$script_dir/agents/${step_name}.md"
    if [[ -f "$agent_file" ]]; then
        echo "$agent_file"
        return 0
    fi

    # Fallback to implement
    log_warn "Agent not found for step: $step_name, using implement"
    echo "builtin:implement"
}

# Export functions
export -f generate_step_prompt
export -f find_agent_file
