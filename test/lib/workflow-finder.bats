#!/usr/bin/env bats
# workflow-finder.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
    
    source "$PROJECT_ROOT/lib/workflow-finder.sh"
    
    # テスト用ディレクトリ構造を作成
    export TEST_DIR="$BATS_TEST_TMPDIR/finder_test"
    mkdir -p "$TEST_DIR/workflows"
    mkdir -p "$TEST_DIR/agents"
    mkdir -p "$TEST_DIR/.pi/agents"
    mkdir -p "$TEST_DIR/.pi"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# find_workflow_file テスト
# ====================

@test "find_workflow_file returns builtin when no file exists" {
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "builtin:default" ]
}

@test "find_workflow_file returns builtin:simple for simple workflow" {
    result="$(find_workflow_file "simple" "$TEST_DIR")"
    [ "$result" = "builtin:simple" ]
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

@test "find_workflow_file finds custom workflow file" {
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
EOF
    
    result="$(find_workflow_file "custom" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/workflows/custom.yaml" ]
}

@test "find_workflow_file prioritizes .pi/workflow.yaml over workflows/" {
    cat > "$TEST_DIR/workflows/default.yaml" << 'EOF'
name: default-from-workflows
steps:
  - plan
EOF
    cat > "$TEST_DIR/.pi/workflow.yaml" << 'EOF'
name: default-from-pi
steps:
  - implement
  - merge
EOF
    
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/.pi/workflow.yaml" ]
}

@test "find_workflow_file prioritizes .pi-runner.yaml over .pi/workflow.yaml" {
    cat > "$TEST_DIR/.pi/workflow.yaml" << 'EOF'
name: pi-workflow
steps:
  - implement
EOF
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflow:
  name: runner-workflow
  steps:
    - plan
    - implement
    - merge
EOF
    
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/.pi-runner.yaml" ]
}

@test "find_workflow_file ignores .pi-runner.yaml without workflow section" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
tmux:
  session_prefix: test
EOF
    cat > "$TEST_DIR/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
EOF
    
    result="$(find_workflow_file "default" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/workflows/default.yaml" ]
}

@test "find_workflow_file uses current directory as default project_root" {
    cd "$TEST_DIR"
    cat > "workflows/default.yaml" << 'EOF'
name: default
steps:
  - implement
EOF
    
    result="$(find_workflow_file "default")"
    [ "$result" = "./workflows/default.yaml" ]
}

# ====================
# find_agent_file テスト
# ====================

@test "find_agent_file returns builtin when no agent file exists" {
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "builtin:plan" ]
}

@test "find_agent_file returns builtin for implement step" {
    result="$(find_agent_file "implement" "$TEST_DIR")"
    [ "$result" = "builtin:implement" ]
}

@test "find_agent_file returns builtin for review step" {
    result="$(find_agent_file "review" "$TEST_DIR")"
    [ "$result" = "builtin:review" ]
}

@test "find_agent_file returns builtin for merge step" {
    result="$(find_agent_file "merge" "$TEST_DIR")"
    [ "$result" = "builtin:merge" ]
}

@test "find_agent_file returns agents/plan.md when exists" {
    echo "# Custom Plan Agent" > "$TEST_DIR/agents/plan.md"
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/plan.md" ]
}

@test "find_agent_file prioritizes agents/ over .pi/agents/" {
    echo "# Custom Agent" > "$TEST_DIR/agents/plan.md"
    echo "# Pi Agent" > "$TEST_DIR/.pi/agents/plan.md"
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/plan.md" ]
}

@test "find_agent_file falls back to .pi/agents/ when agents/ not found" {
    echo "# Pi Agent" > "$TEST_DIR/.pi/agents/implement.md"
    
    result="$(find_agent_file "implement" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/.pi/agents/implement.md" ]
}

@test "find_agent_file handles custom step names" {
    echo "# Custom Step Agent" > "$TEST_DIR/agents/test.md"
    
    result="$(find_agent_file "test" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/test.md" ]
}

@test "find_agent_file returns builtin for unknown steps" {
    result="$(find_agent_file "unknown-step" "$TEST_DIR")"
    [ "$result" = "builtin:unknown-step" ]
}

@test "find_agent_file uses current directory as default project_root" {
    cd "$TEST_DIR"
    echo "# Agent" > "agents/plan.md"
    
    result="$(find_agent_file "plan")"
    [ "$result" = "./agents/plan.md" ]
}

# ====================
# エッジケーステスト
# ====================

@test "find_workflow_file handles empty project root" {
    empty_dir="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "$empty_dir"
    
    result="$(find_workflow_file "default" "$empty_dir")"
    [ "$result" = "builtin:default" ]
}

@test "find_agent_file handles empty project root" {
    empty_dir="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "$empty_dir"
    
    result="$(find_agent_file "plan" "$empty_dir")"
    [ "$result" = "builtin:plan" ]
}

@test "find_workflow_file handles workflow name with special characters" {
    cat > "$TEST_DIR/workflows/my-custom-workflow.yaml" << 'EOF'
name: my-custom-workflow
steps:
  - implement
EOF
    
    result="$(find_workflow_file "my-custom-workflow" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/workflows/my-custom-workflow.yaml" ]
}

@test "find_agent_file handles step name with hyphen" {
    echo "# Test Agent" > "$TEST_DIR/agents/pre-check.md"
    
    result="$(find_agent_file "pre-check" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/pre-check.md" ]
}

@test "find_agent_file handles step name with underscore" {
    echo "# Test Agent" > "$TEST_DIR/agents/code_review.md"
    
    result="$(find_agent_file "code_review" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/code_review.md" ]
}
