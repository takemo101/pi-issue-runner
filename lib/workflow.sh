#!/usr/bin/env bash
# ============================================================================
# lib/workflow.sh - Simple workflow engine
# ============================================================================

set -euo pipefail

_WORKFLOW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_LIB_DIR/workflow-loader.sh"
source "$_WORKFLOW_LIB_DIR/workflow-prompt.sh"
source "$_WORKFLOW_LIB_DIR/config.sh"
source "$_WORKFLOW_LIB_DIR/log.sh"

# ============================================================================
# Workflow Resolution
# ============================================================================

# Resolve default workflow name
# Returns "auto" if .pi-runner.yaml has workflows section, else "default"
resolve_default_workflow() {
    local project_root="${1:-.}"
    local config_file="$project_root/.pi-runner.yaml"
    
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows"; then
        echo "auto"
    else
        echo "default"
    fi
}

# Find workflow file
# Usage: find_workflow_file <workflow_name> [project_root]
find_workflow_file() {
    local workflow_name="${1:-default}"
    local project_root="${2:-.}"
    
    # Handle special prefixes
    if [[ "$workflow_name" == builtin:* ]] || [[ "$workflow_name" == config-workflow:* ]]; then
        echo "$workflow_name"
        return 0
    fi
    
    # Check .pi-runner.yaml workflows section
    local config_file="$project_root/.pi-runner.yaml"
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows.${workflow_name}"; then
        echo "config-workflow:$workflow_name"
        return 0
    fi
    
    # Check workflows/ directory
    local workflow_file="$project_root/workflows/${workflow_name}.yaml"
    if [[ -f "$workflow_file" ]]; then
        echo "$workflow_file"
        return 0
    fi
    
    # Check .pi/workflows.yaml
    workflow_file="$project_root/.pi/workflows.yaml"
    if [[ -f "$workflow_file" ]]; then
        echo "$workflow_file"
        return 0
    fi
    
    # Fallback to builtin
    if [[ "$workflow_name" == "simple" ]]; then
        echo "builtin:simple"
    else
        echo "builtin:default"
    fi
}

# ============================================================================
# Workflow Execution
# ============================================================================

# Execute a workflow step
# Usage: execute_step <step_name> <step_context> <issue_number> <issue_title> <issue_body> <branch_name> <worktree_path> [project_root] [workflow_name]
execute_step() {
    local step_name="$1"
    local step_context="$2"
    local issue_number="$3"
    local issue_title="$4"
    local issue_body="$5"
    local branch_name="$6"
    local worktree_path="$7"
    local project_root="${8:-.}"
    local workflow_name="${9:-default}"
    
    log_info "Executing step: $step_name"
    
    # Generate prompt
    local prompt
    prompt=$(generate_step_prompt "$step_name" "$step_context" "$issue_number" "$issue_title" "$issue_body" "$branch_name" "$worktree_path" "$project_root" "$workflow_name")
    
    # Get pi command
    local pi_cmd
    pi_cmd="$(get_config pi_command)"
    
    # Execute pi with prompt
    echo "$prompt" | $pi_cmd
}

# List available workflows
list_available_workflows() {
    local project_root="${1:-.}"
    
    echo "Available workflows:"
    echo ""
    
    # Builtin workflows
    echo "  [builtin] default  - Full workflow (plan → implement → review → merge)"
    echo "  [builtin] simple   - Simple workflow (implement → merge)"
    echo ""
    
    # Config workflows
    local config_file="$project_root/.pi-runner.yaml"
    if [[ -f "$config_file" ]] && yaml_exists "$config_file" ".workflows"; then
        echo "  [config] workflows from .pi-runner.yaml:"
        yq -r '.workflows | keys[]' "$config_file" 2>/dev/null | while read -r name; do
            local desc
            desc=$(yq -r ".workflows.${name}.description // \"\"" "$config_file" 2>/dev/null)
            printf "    %-20s %s\n" "$name" "$desc"
        done
        echo ""
    fi
    
    # File workflows
    if [[ -d "$project_root/workflows" ]]; then
        echo "  [file] workflows/ directory:"
        for f in "$project_root/workflows"/*.yaml; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f" .yaml)
            printf "    %s\n" "$name"
        done
    fi
}

# Export functions
export -f resolve_default_workflow
export -f find_workflow_file
export -f execute_step
export -f list_available_workflows
