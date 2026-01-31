#!/usr/bin/env bats
# workflow-loader.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
    
    source "$PROJECT_ROOT/lib/workflow-loader.sh"
    
    # テスト用ディレクトリ構造を作成
    export TEST_PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/workflows"
    mkdir -p "$TEST_PROJECT/agents"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ビルトインワークフロー定数テスト
# ====================

@test "_BUILTIN_WORKFLOW_DEFAULT is defined" {
    [ -n "$_BUILTIN_WORKFLOW_DEFAULT" ]
}

@test "_BUILTIN_WORKFLOW_DEFAULT contains plan implement review merge" {
    [ "$_BUILTIN_WORKFLOW_DEFAULT" = "plan implement review merge" ]
}

@test "_BUILTIN_WORKFLOW_SIMPLE is defined" {
    [ -n "$_BUILTIN_WORKFLOW_SIMPLE" ]
}

@test "_BUILTIN_WORKFLOW_SIMPLE contains implement merge" {
    [ "$_BUILTIN_WORKFLOW_SIMPLE" = "implement merge" ]
}

# ====================
# get_workflow_steps テスト - ビルトイン
# ====================

@test "get_workflow_steps returns default builtin steps" {
    result="$(get_workflow_steps "builtin:default")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps returns simple builtin steps" {
    result="$(get_workflow_steps "builtin:simple")"
    [ "$result" = "implement merge" ]
}

@test "get_workflow_steps returns default for unknown builtin" {
    result="$(get_workflow_steps "builtin:unknown")"
    [ "$result" = "plan implement review merge" ]
}

# ====================
# get_workflow_steps テスト - YAMLファイル
# ====================

@test "get_workflow_steps parses YAML file with steps" {
    cat > "$TEST_PROJECT/workflows/test.yaml" << 'EOF'
name: test
steps:
  - step1
  - step2
  - step3
EOF
    
    result="$(get_workflow_steps "$TEST_PROJECT/workflows/test.yaml")"
    [ "$result" = "step1 step2 step3" ]
}

@test "get_workflow_steps parses .pi-runner.yaml format" {
    cat > "$TEST_PROJECT/.pi-runner.yaml" << 'EOF'
workflow:
  name: runner
  steps:
    - plan
    - implement
EOF
    
    result="$(get_workflow_steps "$TEST_PROJECT/.pi-runner.yaml")"
    [ "$result" = "plan implement" ]
}

@test "get_workflow_steps returns builtin when file not found" {
    run get_workflow_steps "/nonexistent/file.yaml"
    [ "$status" -eq 1 ]
}

@test "get_workflow_steps returns builtin when no steps in file" {
    cat > "$TEST_PROJECT/workflows/empty.yaml" << 'EOF'
name: empty
description: No steps defined
EOF
    
    result="$(get_workflow_steps "$TEST_PROJECT/workflows/empty.yaml")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps handles single step" {
    cat > "$TEST_PROJECT/workflows/single.yaml" << 'EOF'
name: single
steps:
  - implement
EOF
    
    result="$(get_workflow_steps "$TEST_PROJECT/workflows/single.yaml")"
    [ "$result" = "implement" ]
}

@test "get_workflow_steps handles many steps" {
    cat > "$TEST_PROJECT/workflows/many.yaml" << 'EOF'
name: many
steps:
  - plan
  - design
  - implement
  - test
  - review
  - merge
EOF
    
    result="$(get_workflow_steps "$TEST_PROJECT/workflows/many.yaml")"
    [ "$result" = "plan design implement test review merge" ]
}

# ====================
# get_agent_prompt テスト - ビルトイン
# ====================

@test "get_agent_prompt returns plan agent prompt" {
    result="$(get_agent_prompt "builtin:plan" "42")"
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns implement agent prompt" {
    result="$(get_agent_prompt "builtin:implement" "99")"
    [[ "$result" == *"#99"* ]]
}

@test "get_agent_prompt returns review agent prompt" {
    result="$(get_agent_prompt "builtin:review" "123")"
    [[ "$result" == *"#123"* ]]
}

@test "get_agent_prompt returns merge agent prompt" {
    result="$(get_agent_prompt "builtin:merge" "456")"
    [[ "$result" == *"#456"* ]]
}

@test "get_agent_prompt returns implement for unknown builtin" {
    result="$(get_agent_prompt "builtin:unknown" "42")"
    [[ "$result" == *"#42"* ]]
}

# ====================
# get_agent_prompt テスト - カスタムファイル
# ====================

@test "get_agent_prompt reads from custom file" {
    echo "Custom agent for issue #{{issue_number}}" > "$TEST_PROJECT/agents/custom.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/custom.md" "42")"
    [ "$result" = "Custom agent for issue #42" ]
}

@test "get_agent_prompt expands branch_name variable" {
    echo "Branch: {{branch_name}}" > "$TEST_PROJECT/agents/test.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/test.md" "" "feature/test")"
    [ "$result" = "Branch: feature/test" ]
}

@test "get_agent_prompt expands worktree_path variable" {
    echo "Path: {{worktree_path}}" > "$TEST_PROJECT/agents/test.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/test.md" "" "" "/path/to/worktree")"
    [ "$result" = "Path: /path/to/worktree" ]
}

@test "get_agent_prompt expands step_name variable" {
    echo "Step: {{step_name}}" > "$TEST_PROJECT/agents/test.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/test.md" "" "" "" "implement")"
    [ "$result" = "Step: implement" ]
}

@test "get_agent_prompt expands issue_title variable" {
    echo "Title: {{issue_title}}" > "$TEST_PROJECT/agents/test.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/test.md" "" "" "" "" "Fix bug")"
    [ "$result" = "Title: Fix bug" ]
}

@test "get_agent_prompt expands all variables" {
    cat > "$TEST_PROJECT/agents/full.md" << 'EOF'
Issue #{{issue_number}}: {{issue_title}}
Branch: {{branch_name}}
Path: {{worktree_path}}
Step: {{step_name}}
EOF
    
    result="$(get_agent_prompt "$TEST_PROJECT/agents/full.md" "42" "feature/test" "/path/wt" "plan" "Add feature")"
    [[ "$result" == *"Issue #42: Add feature"* ]]
    [[ "$result" == *"Branch: feature/test"* ]]
    [[ "$result" == *"Path: /path/wt"* ]]
    [[ "$result" == *"Step: plan"* ]]
}

@test "get_agent_prompt fails for non-existent file" {
    run get_agent_prompt "/nonexistent/agent.md" "42"
    [ "$status" -eq 1 ]
}

# ====================
# エッジケーステスト
# ====================

@test "get_agent_prompt handles empty issue_number" {
    echo "Issue #{{issue_number}}" > "$TEST_PROJECT/agents/test.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/test.md" "")"
    [ "$result" = "Issue #" ]
}

@test "get_agent_prompt handles special characters in variables" {
    echo "Title: {{issue_title}}" > "$TEST_PROJECT/agents/test.md"
    result="$(get_agent_prompt "$TEST_PROJECT/agents/test.md" "" "" "" "" "Fix: handle & and < characters")"
    [ "$result" = "Title: Fix: handle & and < characters" ]
}

@test "get_agent_prompt handles multiline template" {
    cat > "$TEST_PROJECT/agents/multiline.md" << 'EOF'
# Agent

Issue: #{{issue_number}}
Branch: {{branch_name}}

## Tasks
1. First task
2. Second task
EOF
    
    result="$(get_agent_prompt "$TEST_PROJECT/agents/multiline.md" "42" "feature/test")"
    [[ "$result" == *"Issue: #42"* ]]
    [[ "$result" == *"Branch: feature/test"* ]]
    [[ "$result" == *"## Tasks"* ]]
}

@test "get_workflow_steps handles YAML with comments" {
    cat > "$TEST_PROJECT/workflows/commented.yaml" << 'EOF'
# This is a comment
name: commented
# Another comment
steps:
  - plan
  # Step comment
  - implement
EOF
    
    result="$(get_workflow_steps "$TEST_PROJECT/workflows/commented.yaml")"
    [ "$result" = "plan implement" ]
}
