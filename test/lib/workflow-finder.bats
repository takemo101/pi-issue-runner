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
    export TEST_PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/workflows"
    mkdir -p "$TEST_PROJECT/agents"
    mkdir -p "$TEST_PROJECT/.pi/agents"
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
    result="$(find_workflow_file "default" "$TEST_PROJECT")"
    [ "$result" = "builtin:default" ]
}

@test "find_workflow_file returns builtin:simple for simple workflow" {
    result="$(find_workflow_file "simple" "$TEST_PROJECT")"
    [ "$result" = "builtin:simple" ]
}

@test "find_workflow_file returns workflows/{name}.yaml when exists" {
    cat > "$TEST_PROJECT/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
  - implement
EOF
    
    result="$(find_workflow_file "default" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/workflows/default.yaml" ]
}

@test "find_workflow_file returns workflows/custom.yaml for custom workflow" {
    cat > "$TEST_PROJECT/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - step1
  - step2
EOF
    
    result="$(find_workflow_file "custom" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/workflows/custom.yaml" ]
}

@test "find_workflow_file prioritizes .pi/workflow.yaml over workflows/" {
    cat > "$TEST_PROJECT/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
EOF
    mkdir -p "$TEST_PROJECT/.pi"
    cat > "$TEST_PROJECT/.pi/workflow.yaml" << 'EOF'
name: pi-custom
steps:
  - implement
  - merge
EOF
    
    result="$(find_workflow_file "default" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/.pi/workflow.yaml" ]
}

@test "find_workflow_file prioritizes .pi-runner.yaml with workflow section" {
    cat > "$TEST_PROJECT/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
EOF
    mkdir -p "$TEST_PROJECT/.pi"
    cat > "$TEST_PROJECT/.pi/workflow.yaml" << 'EOF'
name: pi-custom
steps:
  - implement
EOF
    cat > "$TEST_PROJECT/.pi-runner.yaml" << 'EOF'
workflow:
  name: runner
  steps:
    - custom-step
EOF
    
    result="$(find_workflow_file "default" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/.pi-runner.yaml" ]
}

@test "find_workflow_file ignores .pi-runner.yaml without workflow section" {
    cat > "$TEST_PROJECT/.pi-runner.yaml" << 'EOF'
worktree:
  base_dir: .worktrees
EOF
    cat > "$TEST_PROJECT/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
EOF
    
    result="$(find_workflow_file "default" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/workflows/default.yaml" ]
}

@test "find_workflow_file uses current directory when project_root not specified" {
    cd "$TEST_PROJECT"
    cat > "$TEST_PROJECT/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
EOF
    
    result="$(find_workflow_file "default")"
    [ "$result" = "./workflows/default.yaml" ]
}

# ====================
# find_agent_file テスト
# ====================

@test "find_agent_file returns builtin when no agent file exists" {
    result="$(find_agent_file "plan" "$TEST_PROJECT")"
    [ "$result" = "builtin:plan" ]
}

@test "find_agent_file returns builtin for all builtin agents" {
    result_plan="$(find_agent_file "plan" "$TEST_PROJECT")"
    result_implement="$(find_agent_file "implement" "$TEST_PROJECT")"
    result_review="$(find_agent_file "review" "$TEST_PROJECT")"
    result_merge="$(find_agent_file "merge" "$TEST_PROJECT")"
    
    [ "$result_plan" = "builtin:plan" ]
    [ "$result_implement" = "builtin:implement" ]
    [ "$result_review" = "builtin:review" ]
    [ "$result_merge" = "builtin:merge" ]
}

@test "find_agent_file returns agents/{step}.md when exists" {
    echo "Custom plan agent" > "$TEST_PROJECT/agents/plan.md"
    result="$(find_agent_file "plan" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/agents/plan.md" ]
}

@test "find_agent_file prioritizes agents/ over .pi/agents/" {
    echo "Custom agent in agents/" > "$TEST_PROJECT/agents/implement.md"
    echo "Custom agent in .pi/agents/" > "$TEST_PROJECT/.pi/agents/implement.md"
    
    result="$(find_agent_file "implement" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/agents/implement.md" ]
}

@test "find_agent_file falls back to .pi/agents/ when agents/ not found" {
    echo "Agent in .pi/agents/" > "$TEST_PROJECT/.pi/agents/review.md"
    
    result="$(find_agent_file "review" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/.pi/agents/review.md" ]
}

@test "find_agent_file handles custom step names" {
    echo "Custom step agent" > "$TEST_PROJECT/agents/custom-step.md"
    result="$(find_agent_file "custom-step" "$TEST_PROJECT")"
    [ "$result" = "$TEST_PROJECT/agents/custom-step.md" ]
}

@test "find_agent_file uses current directory when project_root not specified" {
    cd "$TEST_PROJECT"
    echo "Plan agent" > "$TEST_PROJECT/agents/plan.md"
    
    result="$(find_agent_file "plan")"
    [ "$result" = "./agents/plan.md" ]
}

# ====================
# エッジケーステスト
# ====================

@test "find_workflow_file handles non-existent project root gracefully" {
    result="$(find_workflow_file "default" "/nonexistent/path")"
    [ "$result" = "builtin:default" ]
}

@test "find_agent_file handles non-existent project root gracefully" {
    result="$(find_agent_file "plan" "/nonexistent/path")"
    [ "$result" = "builtin:plan" ]
}

@test "find_workflow_file handles empty workflow name" {
    result="$(find_workflow_file "" "$TEST_PROJECT")"
    [ "$result" = "builtin:default" ]
}

@test "find_workflow_file preserves workflow name in builtin result" {
    result="$(find_workflow_file "thorough" "$TEST_PROJECT")"
    [ "$result" = "builtin:thorough" ]
}
