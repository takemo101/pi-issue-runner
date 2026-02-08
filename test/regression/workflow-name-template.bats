#!/usr/bin/env bats
# Regression test for Issue #1074
# Ensures get_agent_prompt() passes workflow_name correctly

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # Create a test agent template with workflow_name variable
    TEST_AGENT_FILE="$BATS_TEST_TMPDIR/test-agent.md"
    cat > "$TEST_AGENT_FILE" << 'EOF'
# Test Agent for {{workflow_name}}

Issue: {{issue_number}}
Workflow: {{workflow_name}}
EOF
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "Issue #1074: get_agent_prompt passes actual workflow_name instead of 'default'" {
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    
    local result
    result=$(get_agent_prompt "$TEST_AGENT_FILE" "42" "feature/test" "/path/to/worktree" "implement" "Test Issue" "123" "custom-workflow")
    
    # Verify workflow_name is expanded to "custom-workflow" not "default"
    [[ "$result" == *"Workflow: custom-workflow"* ]]
    [[ "$result" != *"Workflow: default"* ]]
    [[ "$result" == *"Issue: 42"* ]]
}

@test "Issue #1074: get_agent_prompt uses 'default' when workflow_name not provided" {
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    
    local result
    result=$(get_agent_prompt "$TEST_AGENT_FILE" "42" "feature/test" "/path/to/worktree" "implement" "Test Issue" "123")
    
    # When workflow_name is not provided, it should default to "default"
    [[ "$result" == *"Workflow: default"* ]]
}

@test "Issue #1074: generate_workflow_prompt passes workflow_name to agent prompts" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    # Create a test workflow with single step
    TEST_WORKFLOW="$BATS_TEST_TMPDIR/test-workflow.yaml"
    cat > "$TEST_WORKFLOW" << 'EOF'
name: test-workflow
description: Test workflow
steps:
  - implement
EOF
    
    # Create agent directory with test agent
    mkdir -p "$BATS_TEST_TMPDIR/agents"
    cat > "$BATS_TEST_TMPDIR/agents/implement.md" << 'EOF'
# Implement Agent

Workflow: {{workflow_name}}
Issue: {{issue_number}}
EOF
    
    local result
    result=$(generate_workflow_prompt "test-workflow" "42" "Test Issue" "Test Body" "feature/test" "/path/to/worktree" "$BATS_TEST_TMPDIR")
    
    # Verify the workflow name is passed correctly
    [[ "$result" == *"## Workflow: test-workflow"* ]]
    [[ "$result" == *"Workflow: test-workflow"* ]]
    [[ "$result" != *"Workflow: default"* ]]
}

@test "Issue #1074: workflow_name is available in all built-in agent templates" {
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    
    # Test each built-in agent
    for agent in plan implement review merge test ci-fix; do
        local result
        result=$(get_agent_prompt "builtin:$agent" "42" "feature/test" "/path/to/worktree" "$agent" "Test Issue" "123" "custom-workflow")
        
        # Verify the prompt is generated (no errors)
        [[ -n "$result" ]]
        
        # Built-in templates don't use {{workflow_name}}, but it should not cause errors
        # The function should accept and pass it correctly
    done
}
