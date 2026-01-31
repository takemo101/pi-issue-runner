#!/usr/bin/env bats
# workflow.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    
    # テスト用ディレクトリ構造を作成
    export TEST_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT_ROOT/workflows"
    mkdir -p "$TEST_PROJECT_ROOT/agents"
    mkdir -p "$TEST_PROJECT_ROOT/.pi/agents"
    
    # yqキャッシュをリセット
    unset _YQ_CHECK_RESULT
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# find_workflow_file テスト
# ====================

@test "find_workflow_file returns builtin when no files exist" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_workflow_file "default" "$TEST_PROJECT_ROOT")"
    [ "$result" = "builtin:default" ]
}

@test "find_workflow_file finds workflows/default.yaml" {
    cat > "$TEST_PROJECT_ROOT/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
  - implement
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_workflow_file "default" "$TEST_PROJECT_ROOT")"
    [ "$result" = "$TEST_PROJECT_ROOT/workflows/default.yaml" ]
}

@test "find_workflow_file finds custom workflow" {
    cat > "$TEST_PROJECT_ROOT/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - test
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_workflow_file "custom" "$TEST_PROJECT_ROOT")"
    [ "$result" = "$TEST_PROJECT_ROOT/workflows/custom.yaml" ]
}

@test "find_workflow_file finds .pi/workflow.yaml" {
    mkdir -p "$TEST_PROJECT_ROOT/.pi"
    cat > "$TEST_PROJECT_ROOT/.pi/workflow.yaml" << 'EOF'
name: project
steps:
  - build
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_workflow_file "default" "$TEST_PROJECT_ROOT")"
    [ "$result" = "$TEST_PROJECT_ROOT/.pi/workflow.yaml" ]
}

# ====================
# find_agent_file テスト
# ====================

@test "find_agent_file returns builtin for missing agent" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_agent_file "plan" "$TEST_PROJECT_ROOT")"
    [ "$result" = "builtin:plan" ]
}

@test "find_agent_file finds agents/plan.md" {
    cat > "$TEST_PROJECT_ROOT/agents/plan.md" << 'EOF'
# Plan Agent
Custom plan agent.
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_agent_file "plan" "$TEST_PROJECT_ROOT")"
    [ "$result" = "$TEST_PROJECT_ROOT/agents/plan.md" ]
}

@test "find_agent_file finds .pi/agents/plan.md" {
    cat > "$TEST_PROJECT_ROOT/.pi/agents/plan.md" << 'EOF'
# Plan Agent
From .pi directory.
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(find_agent_file "plan" "$TEST_PROJECT_ROOT")"
    [ "$result" = "$TEST_PROJECT_ROOT/.pi/agents/plan.md" ]
}

# ====================
# get_workflow_steps テスト
# ====================

@test "get_workflow_steps returns builtin default steps" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(get_workflow_steps "builtin:default")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps returns builtin simple steps" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(get_workflow_steps "builtin:simple")"
    [ "$result" = "implement merge" ]
}

@test "get_workflow_steps parses YAML file with yq" {
    if ! command -v yq &>/dev/null; then
        skip "yq not installed"
    fi
    
    cat > "$TEST_PROJECT_ROOT/workflows/test.yaml" << 'EOF'
name: test
steps:
  - step1
  - step2
  - step3
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(get_workflow_steps "$TEST_PROJECT_ROOT/workflows/test.yaml")"
    [ "$result" = "step1 step2 step3" ]
}

# ====================
# render_template テスト
# ====================

@test "render_template replaces issue_number" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(render_template "Issue #{{issue_number}}" "42")"
    [ "$result" = "Issue #42" ]
}

@test "render_template replaces branch_name" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(render_template "Branch: {{branch_name}}" "" "feature/test")"
    [ "$result" = "Branch: feature/test" ]
}

@test "render_template replaces multiple variables" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    template="Issue #{{issue_number}} on {{branch_name}} in {{worktree_path}}"
    result="$(render_template "$template" "42" "feature/test" "/path/to/worktree")"
    
    [ "$result" = "Issue #42 on feature/test in /path/to/worktree" ]
}

@test "render_template replaces issue_title" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(render_template "Title: {{issue_title}}" "42" "" "" "" "default" "Test Issue")"
    [ "$result" = "Title: Test Issue" ]
}

@test "render_template handles empty variables" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(render_template "Issue #{{issue_number}}" "")"
    [ "$result" = "Issue #" ]
}

# ====================
# get_agent_prompt テスト
# ====================

@test "get_agent_prompt returns builtin plan prompt" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(get_agent_prompt "builtin:plan" "42")"
    [[ "$result" == *"Plan the implementation"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns builtin implement prompt" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(get_agent_prompt "builtin:implement" "42")"
    [[ "$result" == *"Implement the changes"* ]]
}

@test "get_agent_prompt reads from file" {
    cat > "$TEST_PROJECT_ROOT/agents/custom.md" << 'EOF'
# Custom Agent for Issue #{{issue_number}}
Do custom work.
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(get_agent_prompt "$TEST_PROJECT_ROOT/agents/custom.md" "99")"
    [[ "$result" == *"Custom Agent for Issue #99"* ]]
    [[ "$result" == *"Do custom work"* ]]
}

# ====================
# parse_step_result テスト
# ====================

@test "parse_step_result detects DONE" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(parse_step_result "[DONE] All done")"
    [ "$result" = "DONE" ]
}

@test "parse_step_result detects BLOCKED" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(parse_step_result "[BLOCKED] Cannot proceed")"
    [ "$result" = "BLOCKED" ]
}

@test "parse_step_result detects FIX_NEEDED" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(parse_step_result "[FIX_NEEDED] Please fix")"
    [ "$result" = "FIX_NEEDED" ]
}

@test "parse_step_result defaults to DONE" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(parse_step_result "No marker here")"
    [ "$result" = "DONE" ]
}

# ====================
# run_step テスト
# ====================

@test "run_step returns agent prompt" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(run_step "plan" "42" "feature/test" "/path" "$TEST_PROJECT_ROOT")"
    [[ "$result" == *"Plan"* ]] || [[ "$result" == *"plan"* ]]
}

# ====================
# run_workflow テスト
# ====================

@test "run_workflow outputs step info" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(run_workflow "default" "42" "feature/test" "/path" "$TEST_PROJECT_ROOT")"
    
    [[ "$result" == *"step:0:"* ]]
    [[ "$result" == *"total:"* ]]
}

# ====================
# generate_workflow_prompt テスト
# ====================

@test "generate_workflow_prompt includes issue info" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(generate_workflow_prompt "default" "42" "Test Issue" "Issue body" "feature/test" "/path" "$TEST_PROJECT_ROOT")"
    
    [[ "$result" == *"Issue #42"* ]]
    [[ "$result" == *"Test Issue"* ]]
    [[ "$result" == *"Issue body"* ]]
}

@test "generate_workflow_prompt includes all steps" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(generate_workflow_prompt "default" "42" "Test" "Body" "branch" "/path" "$TEST_PROJECT_ROOT")"
    
    [[ "$result" == *"Step 1:"* ]]
    [[ "$result" == *"Step 2:"* ]]
}

@test "generate_workflow_prompt includes completion marker instructions" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(generate_workflow_prompt "default" "42" "Test" "Body" "branch" "/path" "$TEST_PROJECT_ROOT")"
    
    [[ "$result" == *"TASK"* ]]
    [[ "$result" == *"COMPLETE"* ]]
    [[ "$result" == *"42"* ]]
}

# ====================
# list_available_workflows テスト
# ====================

@test "list_available_workflows shows builtin workflows" {
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(list_available_workflows "$TEST_PROJECT_ROOT")"
    
    [[ "$result" == *"default"* ]]
    [[ "$result" == *"simple"* ]]
}

@test "list_available_workflows shows custom workflows" {
    cat > "$TEST_PROJECT_ROOT/workflows/myworkflow.yaml" << 'EOF'
name: myworkflow
EOF
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    result="$(list_available_workflows "$TEST_PROJECT_ROOT")"
    
    [[ "$result" == *"myworkflow"* ]]
}
