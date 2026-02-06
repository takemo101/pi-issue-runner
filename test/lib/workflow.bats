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
    reset_yaml_cache
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
    # ビルトインファイルパスまたはbuiltin:defaultを返す
    [[ "$result" == *"/workflows/default.yaml" ]] || [ "$result" = "builtin:default" ]
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
    # ビルトインファイルパスまたはbuiltin:planを返す
    [[ "$result" == *"/agents/plan.md" ]] || [ "$result" = "builtin:plan" ]
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
# get_workflow_steps_array テスト
# ====================

@test "get_workflow_steps_array returns steps for default" {
    result="$(get_workflow_steps_array "default" "/nonexistent")"
    [ "$result" = "plan implement review merge" ]
}

# ====================
# generate_workflow_prompt テスト
# ====================

@test "generate_workflow_prompt includes error marker documentation" {
    result="$(generate_workflow_prompt "default" "42" "Test Issue" "Body" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"###TASK"* ]]
    [[ "$result" == *"_ERROR_"* ]]
    [[ "$result" == *"unrecoverable errors"* ]]
}

@test "generate_workflow_prompt includes completion marker documentation" {
    result="$(generate_workflow_prompt "default" "42" "Test Issue" "Body" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"###TASK"* ]]
    [[ "$result" == *"_COMPLETE_"* ]]
}

@test "generate_workflow_prompt includes issue number in markers" {
    result="$(generate_workflow_prompt "default" "99" "Test Issue" "Body" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"99"* ]]
}

@test "generate_workflow_prompt includes On Error section" {
    result="$(generate_workflow_prompt "default" "42" "Test Issue" "Body" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"### On Error"* ]]
    [[ "$result" == *"manual intervention"* ]]
}

# ====================
# list_available_workflows テスト (Issue #913)
# ====================

@test "list_available_workflows shows builtin workflows" {
    result="$(list_available_workflows "$TEST_DIR")"
    [[ "$result" == *"default:"* ]]
    [[ "$result" == *"simple:"* ]]
    [[ "$result" == *"thorough:"* ]]
    [[ "$result" == *"ci-fix:"* ]]
}

@test "list_available_workflows shows workflows from .pi-runner.yaml" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  quick:
    description: "Quick fix workflow"
    steps:
      - implement
      - merge
  
  custom:
    description: "Custom workflow"
    steps:
      - plan
      - implement
      - review
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    [[ "$result" == *"quick: Quick fix workflow"* ]]
    [[ "$result" == *"custom: Custom workflow"* ]]
}

@test "list_available_workflows shows description from .pi-runner.yaml" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  thorough:
    description: "Custom thorough workflow"
    steps:
      - plan
      - implement
      - test
      - review
      - merge
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    # ビルトインの thorough が .pi-runner.yaml の定義でオーバーライドされる
    [[ "$result" == *"thorough: Custom thorough workflow"* ]]
}

@test "list_available_workflows deduplicates builtin names" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  default:
    description: "Custom default workflow"
    steps:
      - implement
      - merge
  
  ci-fix:
    description: "Custom CI fix"
    steps:
      - ci-fix
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    
    # default と ci-fix がそれぞれ1回のみ表示される
    default_count=$(echo "$result" | grep -c "^default:")
    ci_fix_count=$(echo "$result" | grep -c "^ci-fix:")
    
    [ "$default_count" -eq 1 ]
    [ "$ci_fix_count" -eq 1 ]
    
    # カスタムの description が表示される
    [[ "$result" == *"default: Custom default workflow"* ]]
    [[ "$result" == *"ci-fix: Custom CI fix"* ]]
}

@test "list_available_workflows handles missing workflows section gracefully" {
    # workflows セクションがない .pi-runner.yaml
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflow:
  steps:
    - plan
    - implement
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    
    # ビルトインワークフローのみ表示される（エラーにならない）
    [[ "$result" == *"default:"* ]]
    [[ "$result" == *"simple:"* ]]
    [[ "$result" == *"thorough:"* ]]
    [[ "$result" == *"ci-fix:"* ]]
}

@test "list_available_workflows shows workflows from workflows/*.yaml" {
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - plan
  - implement
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    [[ "$result" == *"custom: (custom workflow file)"* ]]
}

@test "list_available_workflows prioritizes .pi-runner.yaml over workflows/*.yaml" {
    # workflows/ ディレクトリにファイルを作成
    cat > "$TEST_DIR/workflows/myworkflow.yaml" << 'EOF'
name: myworkflow
steps:
  - plan
  - implement
EOF
    
    # .pi-runner.yaml でも同じ名前を定義
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  myworkflow:
    description: "From config"
    steps:
      - implement
      - merge
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    
    # myworkflow が1回のみ表示され、.pi-runner.yaml の description が使われる
    myworkflow_count=$(echo "$result" | grep -c "^myworkflow:")
    [ "$myworkflow_count" -eq 1 ]
    [[ "$result" == *"myworkflow: From config"* ]]
}

@test "list_available_workflows uses default description for workflows without description" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  nodesc:
    steps:
      - implement
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    [[ "$result" == *"nodesc: (project workflow)"* ]]
}

@test "list_available_workflows output is sorted" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  zebra:
    description: "Z workflow"
    steps:
      - implement
  
  alpha:
    description: "A workflow"
    steps:
      - plan
      - implement
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    
    # ソートされていることを確認（alpha が zebra より前）
    alpha_line=$(echo "$result" | grep -n "^alpha:" | cut -d: -f1)
    zebra_line=$(echo "$result" | grep -n "^zebra:" | cut -d: -f1)
    
    [ "$alpha_line" -lt "$zebra_line" ]
}

@test "list_available_workflows handles empty workflows directory" {
    # workflows/ ディレクトリは存在するが空
    result="$(list_available_workflows "$TEST_DIR")"
    
    # ビルトインワークフローのみ表示される
    [[ "$result" == *"default:"* ]]
    [[ "$result" == *"simple:"* ]]
}

@test "list_available_workflows handles missing workflows directory" {
    # workflows/ ディレクトリが存在しない
    rm -rf "$TEST_DIR/workflows"
    
    result="$(list_available_workflows "$TEST_DIR")"
    
    # ビルトインワークフローのみ表示される（エラーにならない）
    [[ "$result" == *"default:"* ]]
    [[ "$result" == *"simple:"* ]]
}

@test "list_available_workflows handles multiple workflows from different sources" {
    # .pi-runner.yaml に workflows を定義
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  config1:
    description: "Config workflow 1"
    steps:
      - implement
  
  config2:
    description: "Config workflow 2"
    steps:
      - plan
      - implement
EOF
    
    # workflows/ ディレクトリにもファイルを作成
    cat > "$TEST_DIR/workflows/file1.yaml" << 'EOF'
name: file1
steps:
  - implement
  - merge
EOF
    
    result="$(list_available_workflows "$TEST_DIR")"
    
    # ビルトイン、config、ファイルの全てが表示される
    [[ "$result" == *"default:"* ]]
    [[ "$result" == *"config1: Config workflow 1"* ]]
    [[ "$result" == *"config2: Config workflow 2"* ]]
    [[ "$result" == *"file1: (custom workflow file)"* ]]
}

# ===================
# resolve_default_workflow テスト
# ===================

@test "resolve_default_workflow returns auto when workflows section exists" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  frontend:
    description: フロントエンド
    steps:
      - implement
EOF
    
    result="$(resolve_default_workflow "$TEST_DIR")"
    [ "$result" = "auto" ]
}

@test "resolve_default_workflow returns default when workflows section not defined" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflow:
  steps:
    - plan
    - implement
EOF
    
    result="$(resolve_default_workflow "$TEST_DIR")"
    [ "$result" = "default" ]
}

@test "resolve_default_workflow returns default when no config file" {
    result="$(resolve_default_workflow "$TEST_DIR/nonexistent")"
    [ "$result" = "default" ]
}

@test "resolve_default_workflow returns auto with multiple workflows" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  frontend:
    steps:
      - implement
  backend:
    steps:
      - plan
      - implement
EOF
    
    result="$(resolve_default_workflow "$TEST_DIR")"
    [ "$result" = "auto" ]
}
