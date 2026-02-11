#!/usr/bin/env bash
# ============================================================================
# lib/workflow-loader.sh - Workflow loading and parsing (simplified)
# ============================================================================

set -euo pipefail

_WORKFLOW_LOADER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_WORKFLOW_LOADER_LIB_DIR/yaml.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/log.sh"
source "$_WORKFLOW_LOADER_LIB_DIR/config.sh"

# Builtin workflows
_BUILTIN_WORKFLOW_DEFAULT="plan implement review merge"
_BUILTIN_WORKFLOW_SIMPLE="implement merge"

# ============================================================================
# Workflow Loading
# ============================================================================

# Get workflow steps with context
# Output format: step_name<TAB>context (one per line)
get_workflow_steps() {
    local workflow_file="$1"
    
    # Builtin workflows
    if [[ "$workflow_file" == builtin:* ]]; then
        local workflow_name="${workflow_file#builtin:}"
        case "$workflow_name" in
            simple)
                for step in $_BUILTIN_WORKFLOW_SIMPLE; do
                    printf "%s\t\n" "$step"
                done
                ;;
            *)
                for step in $_BUILTIN_WORKFLOW_DEFAULT; do
                    printf "%s\t\n" "$step"
                done
                ;;
        esac
        return 0
    fi
    
    # Config file workflows
    if [[ "$workflow_file" == config-workflow:* ]]; then
        local workflow_name="${workflow_file#config-workflow:}"
        local config_file
        config_file="$(_resolve_config_file)"
        _parse_steps_from_config "$config_file" ".workflows.${workflow_name}.steps"
        return $?
    fi
    
    # File-based workflows
    if [[ ! -f "$workflow_file" ]]; then
        log_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    local yaml_path
    if [[ "$workflow_file" == *".pi-runner.yaml" ]]; then
        yaml_path=".workflow.steps"
    else
        yaml_path=".steps"
    fi
    
    _parse_steps_from_config "$workflow_file" "$yaml_path"
}

# Parse steps from YAML config
# Output: step_name<TAB>context
_parse_steps_from_config() {
    local config_file="$1"
    local yaml_path="$2"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        return 1
    fi
    
    if check_yq; then
        local item_json
        while IFS= read -r item_json; do
            [[ -z "$item_json" ]] && continue
            
            # Check if it's a string (starts with ") or object (starts with {)
            if [[ "$item_json" == '"'* ]]; then
                # String format: "plan"
                local step_name
                step_name="${item_json#\"}"
                step_name="${step_name%\"}"
                printf "%s\t\n" "$step_name"
                continue
            fi
            
            # Object format: {"plan": {"context": "..."}}
            local step_name step_context
            step_name=$(echo "$item_json" | yq -r 'keys[0]' 2>/dev/null) || step_name=""
            
            # Validate step_name
            if [[ -z "$step_name" ]] || [[ "$step_name" == "null" ]]; then
                log_warn "Could not extract step name from: $item_json"
                continue
            fi
            
            # Skip deprecated run/call steps
            if [[ "$step_name" == "run" ]] || [[ "$step_name" == "call" ]]; then
                log_warn "Deprecated step type: $step_name (use AI step with context instead)"
                continue
            fi
            
            step_context=$(echo "$item_json" | yq -r ".${step_name}.context // \"\"" 2>/dev/null) || step_context=""
            
            if [[ -n "$step_name" && "$step_name" != "null" ]]; then
                printf "%s\t%s\n" "$step_name" "$step_context"
            fi
        done < <(yq -r "${yaml_path}[]? // empty | @json" "$config_file" 2>/dev/null)
    else
        # Fallback: parse simple list without yq
        grep -E "^\s*-" "$config_file" | sed 's/^\s*-\s*//;s/"//g' | while read -r step; do
            printf "%s\t\n" "$step"
        done
    fi
}

# Resolve config file path
_resolve_config_file() {
    if [[ -n "${CONFIG_FILE:-}" ]]; then
        echo "$CONFIG_FILE"
    else
        config_file_found 2>/dev/null || echo ".pi-runner.yaml"
    fi
}

# ============================================================================
# Agent Prompt Loading
# ============================================================================

# Get agent prompt with template substitution
get_agent_prompt() {
    local agent_file="$1"
    local issue_number="${2:-}"
    local branch_name="${3:-}"
    local worktree_path="${4:-}"
    local step_name="${5:-}"
    local issue_title="${6:-}"
    local pr_number="${7:-}"
    local workflow_name="${8:-default}"
    
    local prompt
    
    # Builtin agents
    if [[ "$agent_file" == builtin:* ]]; then
        local agent_name="${agent_file#builtin:}"
        prompt="$(_get_builtin_agent "$agent_name")"
    else
        # Load from file
        if [[ ! -f "$agent_file" ]]; then
            log_error "Agent file not found: $agent_file"
            return 1
        fi
        prompt=$(cat "$agent_file")
    fi
    
    # Template substitution
    prompt="${prompt//\{\{issue_number\}\}/$issue_number}"
    prompt="${prompt//\{\{issue_title\}\}/$issue_title}"
    prompt="${prompt//\{\{branch_name\}\}/$branch_name}"
    prompt="${prompt//\{\{worktree_path\}\}/$worktree_path}"
    prompt="${prompt//\{\{step_name\}\}/$step_name}"
    prompt="${prompt//\{\{pr_number\}\}/$pr_number}"
    prompt="${prompt//\{\{workflow_name\}\}/$workflow_name}"
    
    echo "$prompt"
}

# Get builtin agent template
_get_builtin_agent() {
    local agent_name="$1"
    
    case "$agent_name" in
        plan)
            cat << 'EOF'
You are a planning agent for GitHub Issue #{{issue_number}}.

Create a detailed implementation plan based on the issue requirements.
Break down the task into clear, actionable steps.

Output the plan as a markdown document.
EOF
            ;;
        implement)
            cat << 'EOF'
You are an implementation agent for GitHub Issue #{{issue_number}}.

Implement the required changes according to the issue description.
Follow best practices and ensure code quality.

When complete, output: ###TASK_COMPLETE_{{issue_number}}###
EOF
            ;;
        review)
            cat << 'EOF'
You are a review agent for GitHub Issue #{{issue_number}}.

Review the implementation for:
- Code quality
- Best practices
- Issue requirements fulfillment

Provide feedback and suggestions for improvement.
EOF
            ;;
        merge)
            cat << 'EOF'
You are a merge agent for GitHub Issue #{{issue_number}}.

Create a pull request with:
- Clear description
- Link to issue
- Summary of changes

After PR creation, output: ###TASK_COMPLETE_{{issue_number}}###
EOF
            ;;
        test)
            cat << 'EOF'
You are a testing agent for GitHub Issue #{{issue_number}}.

Run tests and verify:
- All tests pass
- No regressions
- Code coverage maintained

Report test results clearly.
EOF
            ;;
        ci-fix)
            cat << 'EOF'
You are a CI fix agent for GitHub Issue #{{issue_number}}.

Analyze CI failures and implement fixes.
Focus on:
- Lint errors
- Test failures
- Build issues

After fixes, output: ###TASK_COMPLETE_{{issue_number}}###
EOF
            ;;
        *)
            log_warn "Unknown builtin agent: $agent_name"
            _get_builtin_agent "implement"
            ;;
    esac
}

# Export functions
export -f get_workflow_steps
export -f get_agent_prompt
