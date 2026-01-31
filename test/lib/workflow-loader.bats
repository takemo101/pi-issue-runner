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
    export TEST_DIR="$BATS_TEST_TMPDIR/loader_test"
    mkdir -p "$TEST_DIR/workflows"
    mkdir -p "$TEST_DIR/agents"
    mkdir -p "$TEST_DIR/.pi"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# get_workflow_steps テスト（ビルトイン）
# ====================

@test "get_workflow_steps returns default steps for builtin:default" {
    result="$(get_workflow_steps "builtin:default")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps returns simple steps for builtin:simple" {
    result="$(get_workflow_steps "builtin:simple")"
    [ "$result" = "implement merge" ]
}

@test "get_workflow_steps returns default for unknown builtin" {
    result="$(get_workflow_steps "builtin:unknown")"
    [ "$result" = "plan implement review merge" ]
}

# ====================
# get_workflow_steps テスト（YAMLファイル）
# ====================

@test "get_workflow_steps parses steps from YAML file" {
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

@test "get_workflow_steps parses single step workflow" {
    cat > "$TEST_DIR/workflows/single.yaml" << 'EOF'
name: single
steps:
  - implement
EOF
    
    result="$(get_workflow_steps "$TEST_DIR/workflows/single.yaml")"
    [ "$result" = "implement" ]
}

@test "get_workflow_steps parses .pi-runner.yaml workflow section" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflow:
  name: custom
  steps:
    - plan
    - implement
    - test
    - merge
EOF
    
    result="$(get_workflow_steps "$TEST_DIR/.pi-runner.yaml")"
    [ "$result" = "plan implement test merge" ]
}

@test "get_workflow_steps returns builtin when no steps in YAML" {
    cat > "$TEST_DIR/workflows/empty.yaml" << 'EOF'
name: empty
# no steps defined
EOF
    
    result="$(get_workflow_steps "$TEST_DIR/workflows/empty.yaml")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps fails for missing file" {
    run get_workflow_steps "$TEST_DIR/nonexistent.yaml"
    [ "$status" -eq 1 ]
}

# ====================
# get_agent_prompt テスト（ビルトイン）
# ====================

@test "get_agent_prompt returns plan prompt for builtin:plan" {
    result="$(get_agent_prompt "builtin:plan" "42")"
    [[ "$result" == *"issue #42"* ]] || [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns implement prompt for builtin:implement" {
    result="$(get_agent_prompt "builtin:implement" "99")"
    [[ "$result" == *"issue #99"* ]] || [[ "$result" == *"#99"* ]]
}

@test "get_agent_prompt returns review prompt for builtin:review" {
    result="$(get_agent_prompt "builtin:review" "123")"
    [[ "$result" == *"issue #123"* ]] || [[ "$result" == *"#123"* ]]
}

@test "get_agent_prompt returns merge prompt for builtin:merge" {
    result="$(get_agent_prompt "builtin:merge" "456")"
    [[ "$result" == *"issue #456"* ]] || [[ "$result" == *"#456"* ]]
}

@test "get_agent_prompt returns implement prompt for unknown builtin" {
    result="$(get_agent_prompt "builtin:unknown" "1")"
    [[ "$result" == *"#1"* ]]
}

# ====================
# get_agent_prompt テスト（カスタムファイル）
# ====================

@test "get_agent_prompt reads from custom file" {
    echo "Custom agent content for issue #{{issue_number}}" > "$TEST_DIR/agents/custom.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/custom.md" "42")"
    [ "$result" = "Custom agent content for issue #42" ]
}

@test "get_agent_prompt expands branch_name variable" {
    echo "Branch: {{branch_name}}" > "$TEST_DIR/agents/branch.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/branch.md" "" "feature/test")"
    [ "$result" = "Branch: feature/test" ]
}

@test "get_agent_prompt expands worktree_path variable" {
    echo "Worktree: {{worktree_path}}" > "$TEST_DIR/agents/worktree.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/worktree.md" "" "" "/path/to/worktree")"
    [ "$result" = "Worktree: /path/to/worktree" ]
}

@test "get_agent_prompt expands step_name variable" {
    echo "Step: {{step_name}}" > "$TEST_DIR/agents/step.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/step.md" "" "" "" "plan")"
    [ "$result" = "Step: plan" ]
}

@test "get_agent_prompt expands issue_title variable" {
    echo "Title: {{issue_title}}" > "$TEST_DIR/agents/title.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/title.md" "" "" "" "" "My Issue Title")"
    [ "$result" = "Title: My Issue Title" ]
}

@test "get_agent_prompt expands all variables" {
    cat > "$TEST_DIR/agents/all.md" << 'EOF'
Issue: #{{issue_number}} - {{issue_title}}
Branch: {{branch_name}}
Worktree: {{worktree_path}}
Step: {{step_name}}
EOF
    
    result="$(get_agent_prompt "$TEST_DIR/agents/all.md" "42" "feature/test" "/path/worktree" "implement" "Test Issue")"
    [[ "$result" == *"Issue: #42 - Test Issue"* ]]
    [[ "$result" == *"Branch: feature/test"* ]]
    [[ "$result" == *"Worktree: /path/worktree"* ]]
    [[ "$result" == *"Step: implement"* ]]
}

@test "get_agent_prompt fails for missing file" {
    run get_agent_prompt "$TEST_DIR/nonexistent.md" "1"
    [ "$status" -eq 1 ]
}

# ====================
# 複数変数展開テスト
# ====================

@test "get_agent_prompt handles multiple same variables" {
    echo "Issue #{{issue_number}}, again #{{issue_number}}" > "$TEST_DIR/agents/multi.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/multi.md" "99")"
    [ "$result" = "Issue #99, again #99" ]
}

@test "get_agent_prompt leaves unknown variables unchanged" {
    echo "Unknown: {{unknown_var}}" > "$TEST_DIR/agents/unknown.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/unknown.md" "1")"
    [ "$result" = "Unknown: {{unknown_var}}" ]
}

# ====================
# エッジケーステスト
# ====================

@test "get_agent_prompt handles empty agent file" {
    touch "$TEST_DIR/agents/empty.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/empty.md" "1")"
    [ -z "$result" ]
}

@test "get_agent_prompt handles multiline agent file" {
    cat > "$TEST_DIR/agents/multiline.md" << 'EOF'
# Agent Title

## Description
This is issue #{{issue_number}}

## Steps
1. First step
2. Second step
EOF
    
    result="$(get_agent_prompt "$TEST_DIR/agents/multiline.md" "42")"
    [[ "$result" == *"# Agent Title"* ]]
    [[ "$result" == *"issue #42"* ]]
    [[ "$result" == *"1. First step"* ]]
}

@test "get_agent_prompt handles special characters in issue title" {
    echo "Title: {{issue_title}}" > "$TEST_DIR/agents/special.md"
    
    result="$(get_agent_prompt "$TEST_DIR/agents/special.md" "" "" "" "" "Fix: bug (issue-1) @test")"
    [ "$result" = "Title: Fix: bug (issue-1) @test" ]
}

@test "get_workflow_steps handles steps with numbers" {
    cat > "$TEST_DIR/workflows/numbered.yaml" << 'EOF'
name: numbered
steps:
  - step1
  - step2
  - step3
EOF
    
    result="$(get_workflow_steps "$TEST_DIR/workflows/numbered.yaml")"
    [ "$result" = "step1 step2 step3" ]
}

# ====================
# ビルトインワークフロー定数テスト
# ====================

@test "_BUILTIN_WORKFLOW_DEFAULT contains plan" {
    [[ "$_BUILTIN_WORKFLOW_DEFAULT" == *"plan"* ]]
}

@test "_BUILTIN_WORKFLOW_DEFAULT contains implement" {
    [[ "$_BUILTIN_WORKFLOW_DEFAULT" == *"implement"* ]]
}

@test "_BUILTIN_WORKFLOW_DEFAULT contains review" {
    [[ "$_BUILTIN_WORKFLOW_DEFAULT" == *"review"* ]]
}

@test "_BUILTIN_WORKFLOW_DEFAULT contains merge" {
    [[ "$_BUILTIN_WORKFLOW_DEFAULT" == *"merge"* ]]
}

@test "_BUILTIN_WORKFLOW_SIMPLE contains implement" {
    [[ "$_BUILTIN_WORKFLOW_SIMPLE" == *"implement"* ]]
}

@test "_BUILTIN_WORKFLOW_SIMPLE contains merge" {
    [[ "$_BUILTIN_WORKFLOW_SIMPLE" == *"merge"* ]]
}

@test "_BUILTIN_WORKFLOW_SIMPLE does not contain plan" {
    [[ "$_BUILTIN_WORKFLOW_SIMPLE" != *"plan"* ]]
}
