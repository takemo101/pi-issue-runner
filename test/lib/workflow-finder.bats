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
    
    # 設定キャッシュをリセット（agents設定テスト用）
    unset _CONFIG_LOADED
    unset CONFIG_AGENTS_PLAN
    unset CONFIG_AGENTS_IMPLEMENT
    unset CONFIG_AGENTS_REVIEW
    unset CONFIG_AGENTS_MERGE
    unset CONFIG_AGENTS_TEST
    unset CONFIG_AGENTS_CI_FIX
    
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

@test "find_agent_file returns builtin for test step" {
    result="$(find_agent_file "test" "$TEST_DIR")"
    [ "$result" = "builtin:test" ]
}

@test "find_agent_file returns builtin for ci-fix step" {
    result="$(find_agent_file "ci-fix" "$TEST_DIR")"
    [ "$result" = "builtin:ci-fix" ]
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

# ====================
# agents設定を参照するテスト
# ====================

@test "find_agent_file uses config path when configured file exists" {
    # カスタムエージェントディレクトリを作成
    mkdir -p "$TEST_DIR/custom/agents"
    echo "# Custom Plan Agent from config" > "$TEST_DIR/custom/agents/my-plan.md"
    
    # デフォルトのagents/plan.mdも作成（設定が優先されることを確認）
    echo "# Default Plan Agent" > "$TEST_DIR/agents/plan.md"
    
    # 設定ファイルを作成
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
agents:
  plan: custom/agents/my-plan.md
EOF
    
    # テストディレクトリに移動して設定を読み込む
    cd "$TEST_DIR"
    reload_config
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/custom/agents/my-plan.md" ]
}

@test "find_agent_file falls back when configured file does not exist" {
    # 設定ファイルは存在するが、指定されたパスのファイルは存在しない
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
agents:
  plan: nonexistent/path/plan.md
EOF
    
    # デフォルトのパスにファイルを作成
    echo "# Default Plan Agent" > "$TEST_DIR/agents/plan.md"
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/plan.md" ]
}

@test "find_agent_file uses config for all default steps" {
    mkdir -p "$TEST_DIR/custom"
    echo "# Custom Plan" > "$TEST_DIR/custom/plan.md"
    echo "# Custom Implement" > "$TEST_DIR/custom/implement.md"
    echo "# Custom Review" > "$TEST_DIR/custom/review.md"
    echo "# Custom Merge" > "$TEST_DIR/custom/merge.md"
    echo "# Custom Test" > "$TEST_DIR/custom/test.md"
    echo "# Custom CI Fix" > "$TEST_DIR/custom/ci-fix.md"
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
agents:
  plan: custom/plan.md
  implement: custom/implement.md
  review: custom/review.md
  merge: custom/merge.md
  test: custom/test.md
  ci-fix: custom/ci-fix.md
EOF
    
    # テストディレクトリに移動して設定を読み込む
    cd "$TEST_DIR"
    reload_config
    
    [ "$(find_agent_file "plan" "$TEST_DIR")" = "$TEST_DIR/custom/plan.md" ]
    [ "$(find_agent_file "implement" "$TEST_DIR")" = "$TEST_DIR/custom/implement.md" ]
    [ "$(find_agent_file "review" "$TEST_DIR")" = "$TEST_DIR/custom/review.md" ]
    [ "$(find_agent_file "merge" "$TEST_DIR")" = "$TEST_DIR/custom/merge.md" ]
    [ "$(find_agent_file "test" "$TEST_DIR")" = "$TEST_DIR/custom/test.md" ]
    [ "$(find_agent_file "ci-fix" "$TEST_DIR")" = "$TEST_DIR/custom/ci-fix.md" ]
}

@test "find_agent_file handles absolute path in config" {
    mkdir -p "$TEST_DIR/absolute"
    echo "# Absolute Path Agent" > "$TEST_DIR/absolute/plan.md"
    local abs_path="$TEST_DIR/absolute/plan.md"
    
    # 絶対パスを設定
    cat > "$TEST_DIR/.pi-runner.yaml" << EOF
agents:
  plan: $abs_path
EOF
    
    # テストディレクトリに移動して設定を読み込む
    cd "$TEST_DIR"
    reload_config
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$abs_path" ]
}

@test "find_agent_file ignores config for unknown steps" {
    # 未知のステップに対しては設定が無視され、通常の検索順序が使用される
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
agents:
  unknown_step: custom/unknown.md
EOF
    
    echo "# Custom Agent" > "$TEST_DIR/agents/unknown_step.md"
    
    result="$(find_agent_file "unknown_step" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/unknown_step.md" ]
}

@test "find_agent_file prioritizes agents/ over config when config file missing" {
    # 設定は存在するがファイルが見つからない場合、通常の検索順序を使用
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
agents:
  plan: missing/custom-plan.md
EOF
    
    echo "# Agents Dir Plan" > "$TEST_DIR/agents/plan.md"
    echo "# Pi Agents Plan" > "$TEST_DIR/.pi/agents/plan.md"
    
    result="$(find_agent_file "plan" "$TEST_DIR")"
    [ "$result" = "$TEST_DIR/agents/plan.md" ]
}
