#!/usr/bin/env bats
# workflow.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    # テスト用ディレクトリ
    export TEST_DIR="$BATS_TEST_TMPDIR/workflow_test"
    mkdir -p "$TEST_DIR/workflows"
    mkdir -p "$TEST_DIR/agents"
    mkdir -p "$TEST_DIR/.pi/agents"
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# check_yq テスト
# ====================

@test "check_yq returns correct status" {
    if command -v yq &>/dev/null; then
        run check_yq
        [ "$status" -eq 0 ]
    else
        run check_yq
        [ "$status" -eq 1 ]
    fi
}

@test "check_yq caches result" {
    _YQ_CHECK_RESULT=""
    check_yq || true
    [ -n "$_YQ_CHECK_RESULT" ]
}

# ====================
# find_workflow_file テスト
# ====================

@test "find_workflow_file returns builtin when no file exists" {
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "builtin:default" ]
}

@test "find_workflow_file returns workflows/default.yaml when exists" {
    cat > "$TEST_DIR/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
  - implement
EOF
    
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/workflows/default.yaml" ]
}

@test "find_workflow_file prioritizes .pi/workflow.yaml" {
    cat > "$TEST_DIR/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
EOF
    cat > "$TEST_DIR/.pi/workflow.yaml" << 'EOF'
name: custom
steps:
  - implement
  - merge
EOF
    
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/.pi/workflow.yaml" ]
}

# ====================
# find_agent_file テスト
# ====================

@test "find_agent_file returns builtin when no agent file exists" {
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "builtin:plan" ]
}

@test "find_agent_file returns agents/plan.md when exists" {
    echo "Custom plan agent" > "$TEST_DIR/agents/plan.md"
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/plan.md" ]
}

@test "find_agent_file agents/ takes priority over .pi/agents/" {
    echo "Custom plan agent" > "$TEST_DIR/agents/plan.md"
    echo "Pi plan agent" > "$TEST_DIR/.pi/agents/plan.md"
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/plan.md" ]
}

@test "find_agent_file falls back to .pi/agents/ when agents/ not found" {
    echo "Pi plan agent" > "$TEST_DIR/.pi/agents/plan.md"
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/.pi/agents/plan.md" ]
}

# ====================
# get_workflow_steps テスト
# ====================

@test "get_workflow_steps returns builtin default workflow steps" {
    result="$(get_workflow_steps "builtin:default")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps returns builtin simple workflow steps" {
    result="$(get_workflow_steps "builtin:simple")"
    [ "$result" = "implement merge" ]
}

@test "get_workflow_steps parses YAML file" {
    if ! command -v yq &>/dev/null; then
        skip "yq not available"
    fi
    
    cat > "$TEST_DIR/workflows/test.yaml" << 'EOF'
name: test
steps:
  - step1
  - step2
  - step3
EOF
    
    result="$(get_workflow_steps "$TEST_DIR/workflows/test.yaml")"
    [ "$result" = "step1 step2 step3" ]
}

# ====================
# get_agent_prompt テスト
# ====================

@test "get_agent_prompt builtin plan contains issue number" {
    result="$(get_agent_prompt "builtin:plan" "42")"
    [[ "$result" == *"issue #42"* ]] || [[ "$result" == *"Issue #42"* ]] || [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt builtin implement contains issue number" {
    result="$(get_agent_prompt "builtin:implement" "99")"
    [[ "$result" == *"issue #99"* ]] || [[ "$result" == *"Issue #99"* ]] || [[ "$result" == *"#99"* ]]
}

@test "get_agent_prompt with custom agent file" {
    echo "Custom agent for issue #{{issue_number}}" > "$TEST_DIR/agents/custom.md"
    result="$(get_agent_prompt "$TEST_DIR/agents/custom.md" "123")"
    [ "$result" = "Custom agent for issue #123" ]
}

@test "get_agent_prompt with issue_title" {
    echo "Issue #{{issue_number}}: {{issue_title}}" > "$TEST_DIR/agents/with_title.md"
    result="$(get_agent_prompt "$TEST_DIR/agents/with_title.md" "42" "" "" "" "My Issue Title")"
    [ "$result" = "Issue #42: My Issue Title" ]
}

# ====================
# parse_step_result テスト
# ====================

@test "parse_step_result detects DONE marker" {
    result="$(parse_step_result "Task completed [DONE]")"
    [ "$result" = "DONE" ]
}

@test "parse_step_result detects BLOCKED marker" {
    result="$(parse_step_result "Cannot proceed [BLOCKED] due to missing info")"
    [ "$result" = "BLOCKED" ]
}

@test "parse_step_result detects FIX_NEEDED marker" {
    result="$(parse_step_result "Found issues [FIX_NEEDED]")"
    [ "$result" = "FIX_NEEDED" ]
}

@test "parse_step_result defaults to DONE when no marker" {
    result="$(parse_step_result "Some output without marker")"
    [ "$result" = "DONE" ]
}

# ====================
# run_step テスト
# ====================

@test "run_step with builtin agent returns prompt" {
    result="$(run_step "plan" "42" "feature/test" "/path/worktree" "$TEST_DIR")"
    [[ "$result" == *"issue #42"* ]] || [[ "$result" == *"Issue #42"* ]] || [[ "$result" == *"#42"* ]]
}

@test "run_step with custom agent" {
    echo "Custom step for #{{issue_number}} on {{branch_name}}" > "$TEST_DIR/agents/custom.md"
    result="$(run_step "custom" "55" "feature/custom" "/path" "$TEST_DIR")"
    [ "$result" = "Custom step for #55 on feature/custom" ]
}

# ====================
# run_workflow テスト
# ====================

@test "run_workflow outputs step:0:plan" {
    result="$(run_workflow "default" "42" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"step:0:plan"* ]]
}

@test "run_workflow outputs step:1:implement" {
    result="$(run_workflow "default" "42" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"step:1:implement"* ]]
}

@test "run_workflow outputs step:2:review" {
    result="$(run_workflow "default" "42" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"step:2:review"* ]]
}

@test "run_workflow outputs step:3:merge" {
    result="$(run_workflow "default" "42" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"step:3:merge"* ]]
}

@test "run_workflow outputs total:4" {
    result="$(run_workflow "default" "42" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"total:4"* ]]
}

@test "run_workflow simple workflow outputs step:0:implement" {
    result="$(run_workflow "simple" "42" "" "" "$TEST_DIR")"
    [[ "$result" == *"step:0:implement"* ]]
}

@test "run_workflow simple workflow outputs step:1:merge" {
    result="$(run_workflow "simple" "42" "" "" "$TEST_DIR")"
    [[ "$result" == *"step:1:merge"* ]]
}

@test "run_workflow simple workflow outputs total:2" {
    result="$(run_workflow "simple" "42" "" "" "$TEST_DIR")"
    [[ "$result" == *"total:2"* ]]
}

# ====================
# get_workflow_steps_array テスト
# ====================

@test "get_workflow_steps_array returns steps for default" {
    result="$(get_workflow_steps_array "default" "/nonexistent")"
    [ "$result" = "plan implement review merge" ]
}
