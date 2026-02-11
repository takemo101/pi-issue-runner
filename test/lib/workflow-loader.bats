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
    
    # YAMLキャッシュをリセット（並列テストでのキャッシュ汚染防止）
    reset_yaml_cache
    
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

# ====================
# ビルトインプロンプトフォールバック動作テスト
# ====================

@test "get_agent_prompt returns plan prompt when builtin:plan specified" {
    result="$(get_agent_prompt "builtin:plan" "42")"
    [[ "$result" == *"Plan the implementation"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns implement prompt when builtin:implement specified" {
    result="$(get_agent_prompt "builtin:implement" "42")"
    [[ "$result" == *"Implement the changes"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns review prompt when builtin:review specified" {
    result="$(get_agent_prompt "builtin:review" "42")"
    [[ "$result" == *"Review the implementation"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns merge prompt when builtin:merge specified" {
    result="$(get_agent_prompt "builtin:merge" "42")"
    [[ "$result" == *"Create a PR and merge"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns test prompt when builtin:test specified" {
    result="$(get_agent_prompt "builtin:test" "42")"
    [[ "$result" == *"Test the implementation"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt returns ci-fix prompt when builtin:ci-fix specified" {
    result="$(get_agent_prompt "builtin:ci-fix" "42")"
    [[ "$result" == *"Fix CI failures"* ]] || [[ "$result" == *"Analyze CI logs"* ]]
    [[ "$result" == *"#42"* ]]
}

@test "get_agent_prompt uses implement as fallback for unknown step" {
    result="$(get_agent_prompt "builtin:unknown" "42")"
    [[ "$result" == *"Implement the changes"* ]]
    [[ "$result" == *"#42"* ]]
}

# ====================
# config-workflow:NAME 処理のテスト (Issue #913)
# ====================

@test "get_workflow_steps returns steps for config-workflow:quick" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  quick:
    description: "Quick fix workflow"
    steps:
      - implement
      - merge
EOF
    
    # CONFIG_FILE を設定
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_steps "config-workflow:quick")"
    [ "$result" = "implement merge" ]
}

@test "get_workflow_steps returns steps for config-workflow with multiple steps" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  thorough:
    description: "Thorough workflow"
    steps:
      - plan
      - implement
      - test
      - review
      - merge
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_steps "config-workflow:thorough")"
    [ "$result" = "plan implement test review merge" ]
}

@test "get_workflow_steps returns builtin when config-workflow steps empty" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  empty:
    description: "Empty workflow"
    steps: []
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_steps "config-workflow:empty")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps returns builtin when config-workflow steps missing" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  nosteps:
    description: "Workflow without steps"
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_steps "config-workflow:nosteps")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps handles missing config file for config-workflow" {
    export CONFIG_FILE="$TEST_DIR/nonexistent.yaml"
    
    result="$(get_workflow_steps "config-workflow:quick")"
    [ "$result" = "plan implement review merge" ]
}

@test "get_workflow_steps handles config-workflow with single step" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  single:
    description: "Single step workflow"
    steps:
      - implement
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_steps "config-workflow:single")"
    [ "$result" = "implement" ]
}

@test "get_workflow_steps handles config-workflow with custom steps" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  custom:
    description: "Custom workflow"
    steps:
      - research
      - design
      - implement
      - validate
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_steps "config-workflow:custom")"
    [ "$result" = "research design implement validate" ]
}

@test "get_workflow_steps handles multiple workflows in config" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  quick:
    steps:
      - implement
      - merge
  
  thorough:
    steps:
      - plan
      - implement
      - test
      - review
      - merge
  
  docs:
    steps:
      - implement
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    # 各ワークフローのステップを正しく取得できることを確認
    result_quick="$(get_workflow_steps "config-workflow:quick")"
    [ "$result_quick" = "implement merge" ]
    
    result_thorough="$(get_workflow_steps "config-workflow:thorough")"
    [ "$result_thorough" = "plan implement test review merge" ]
    
    result_docs="$(get_workflow_steps "config-workflow:docs")"
    [ "$result_docs" = "implement" ]
}

@test "get_workflow_steps uses default CONFIG_FILE when not set" {
    # CONFIG_FILE が未設定の場合は .pi-runner.yaml をデフォルトで使用
    cd "$TEST_DIR"
    cat > ".pi-runner.yaml" << 'EOF'
workflows:
  test:
    steps:
      - implement
      - merge
EOF
    
    unset CONFIG_FILE
    
    result="$(get_workflow_steps "config-workflow:test")"
    [ "$result" = "implement merge" ]
    
    # クリーンアップ
    rm -f ".pi-runner.yaml"
}

# ====================
# get_workflow_context テスト (Issue #914)
# ====================

@test "get_workflow_context returns context for config-workflow:frontend" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  frontend:
    description: "Frontend workflow"
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      ## 技術スタック
      - React / Next.js / TypeScript
      ## 重視すべき点
      - レスポンシブデザイン
      - アクセシビリティ
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_context "config-workflow:frontend")"
    [[ "$result" == *"技術スタック"* ]]
    [[ "$result" == *"React / Next.js / TypeScript"* ]]
    [[ "$result" == *"重視すべき点"* ]]
    [[ "$result" == *"レスポンシブデザイン"* ]]
}

@test "get_workflow_context returns empty for workflow without context" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  quick:
    description: "Quick fix workflow"
    steps:
      - implement
      - merge
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_context "config-workflow:quick")"
    [ -z "$result" ]
}

@test "get_workflow_context returns empty for builtin workflow" {
    result="$(get_workflow_context "builtin:default")"
    [ -z "$result" ]
}

@test "get_workflow_context returns empty for missing config file" {
    export CONFIG_FILE="$TEST_DIR/nonexistent.yaml"
    
    result="$(get_workflow_context "config-workflow:frontend")"
    [ -z "$result" ]
}

@test "get_workflow_context returns empty for missing workflow file" {
    result="$(get_workflow_context "$TEST_DIR/nonexistent.yaml")"
    [ -z "$result" ]
}

@test "get_workflow_context returns context from YAML file" {
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
  - merge
context: |
  ## Custom Context
  - Context line 1
  - Context line 2
EOF
    
    result="$(get_workflow_context "$TEST_DIR/workflows/custom.yaml")"
    [[ "$result" == *"Custom Context"* ]]
    [[ "$result" == *"Context line 1"* ]]
    [[ "$result" == *"Context line 2"* ]]
}

@test "get_workflow_context returns context from .pi-runner.yaml workflow section" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflow:
  steps:
    - plan
    - implement
  context: |
    ## Default Workflow Context
    - Important note
EOF
    
    result="$(get_workflow_context "$TEST_DIR/.pi-runner.yaml")"
    [[ "$result" == *"Default Workflow Context"* ]]
    [[ "$result" == *"Important note"* ]]
}

@test "get_workflow_context handles multiline context with special characters" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  backend:
    steps:
      - plan
      - implement
    context: |
      ## Tech Stack
      - Node.js / Express
      - PostgreSQL (with @prisma/client)
      
      ## Important
      - Use `async/await`
      - Follow REST API design
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_context "config-workflow:backend")"
    [[ "$result" == *"Tech Stack"* ]]
    [[ "$result" == *"Node.js / Express"* ]]
    [[ "$result" == *"@prisma/client"* ]]
    [[ "$result" == *"async/await"* ]]
}

@test "get_workflow_context handles empty context field" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  test:
    steps:
      - implement
    context:
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_context "config-workflow:test")"
    [ -z "$result" ]
}

# ====================
# Issue #1040: context フィールドのサポート確認
# ====================

@test "Issue #1040: workflows/*.yaml supports context field" {
    cat > "$TEST_DIR/workflows/backend.yaml" << 'EOF'
name: backend
description: Backend API workflow
steps:
  - plan
  - implement
  - test
  - review
  - merge
context: |
  ## Tech Stack
  - Node.js / Express / TypeScript
  - PostgreSQL / Prisma
  
  ## Important
  - RESTful API design
  - Input validation
EOF
    
    result="$(get_workflow_context "$TEST_DIR/workflows/backend.yaml")"
    [[ "$result" == *"Tech Stack"* ]]
    [[ "$result" == *"Node.js / Express / TypeScript"* ]]
    [[ "$result" == *"RESTful API design"* ]]
}

@test "Issue #1040: builtin workflows have context" {
    # workflows/default.yaml のコンテキストを読み込めることを確認
    local workflow_file="$PROJECT_ROOT/workflows/default.yaml"
    
    result="$(get_workflow_context "$workflow_file")"
    [[ -n "$result" ]]
    [[ "$result" == *"ワークフローの方針"* ]] || [[ "$result" == *"workflow"* ]]
}

@test "Issue #1040: priority - .pi-runner.yaml overrides workflows/*.yaml" {
    # workflows/*.yaml にコンテキストを設定
    cat > "$TEST_DIR/workflows/frontend.yaml" << 'EOF'
name: frontend
description: Frontend workflow
steps:
  - implement
context: |
  This is from workflows/frontend.yaml
EOF
    
    # .pi-runner.yaml でオーバーライド
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  frontend:
    description: Frontend workflow (overridden)
    steps:
      - plan
      - implement
    context: |
      This is from .pi-runner.yaml
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    # config-workflow:frontend は .pi-runner.yaml を優先
    result="$(get_workflow_context "config-workflow:frontend")"
    [[ "$result" == *".pi-runner.yaml"* ]]
    [[ "$result" != *"workflows/frontend.yaml"* ]]
}

# ====================
# get_all_workflows_info テスト
# ====================

@test "get_all_workflows_info returns all workflows from .pi-runner.yaml" {
    # キャッシュをリセット
    reset_yaml_cache
    _YQ_CHECK_RESULT=""
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
      - merge
  thorough:
    description: 大規模機能開発
    steps:
      - plan
      - implement
      - test
      - review
      - merge
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_all_workflows_info "$TEST_DIR")"
    
    # quick ワークフローが含まれる
    echo "$result" | grep -q "^quick"
    echo "$result" | grep -q "小規模修正"
    echo "$result" | grep -q "implement merge"
    
    # thorough ワークフローが含まれる
    echo "$result" | grep -q "^thorough"
    echo "$result" | grep -q "大規模機能開発"
    echo "$result" | grep -q "plan implement test review merge"
}

@test "get_all_workflows_info includes context field" {
    # キャッシュをリセット
    reset_yaml_cache
    _YQ_CHECK_RESULT=""
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  frontend:
    description: フロントエンド実装
    steps:
      - implement
    context: |
      ## Tech Stack
      - React / Next.js
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_all_workflows_info "$TEST_DIR")"
    
    echo "$result" | grep -q "Tech Stack"
    echo "$result" | grep -q "React / Next.js"
}

@test "get_all_workflows_info falls back to builtin workflows when workflows section not defined" {
    # workflows セクションを持たない設定ファイル
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflow:
  steps:
    - plan
    - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_all_workflows_info "$TEST_DIR")"
    
    # ビルトインワークフローが含まれる（default, simple, ci-fix, thorough）
    echo "$result" | grep -q "^default"
    echo "$result" | grep -q "^simple"
}

@test "get_all_workflows_info returns tab-separated format" {
    # キャッシュをリセット
    reset_yaml_cache
    _YQ_CHECK_RESULT=""
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  test:
    description: テストワークフロー
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_all_workflows_info "$TEST_DIR")"
    
    # タブ区切りであることを確認
    echo "$result" | grep -q $'test\tテストワークフロー\timplement'
}

@test "get_all_workflows_info diagnostic - file exists" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    # ファイルの存在確認
    [ -f "$CONFIG_FILE" ]
}

@test "get_all_workflows_info diagnostic - yaml_exists works" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    # yaml_exists が動作するか確認
    yaml_exists "$CONFIG_FILE" ".workflows"
}

@test "get_all_workflows_info diagnostic - yaml_get_keys returns values" {
    # YAMLキャッシュを明示的にリセット
    reset_yaml_cache
    _YQ_CHECK_RESULT=""
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    # yaml_get_keys が値を返すか確認
    result="$(yaml_get_keys "$CONFIG_FILE" ".workflows")"
    [ -n "$result" ]
}

@test "get_all_workflows_info diagnostic - simple parser works" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    # 簡易パーサーを直接呼び出し
    result="$(_simple_yaml_get_keys "$CONFIG_FILE" ".workflows")"
    [ -n "$result" ]
    [[ "$result" == *"quick"* ]]
}

# ========================================
# get_workflow_agent_config テスト
# ========================================

@test "get_workflow_agent_config returns workflow-specific agent type" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: claude
      args:
        - --model
        - claude-sonnet-4-5
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_agent_config "feature" "type")"
    [ "$result" = "claude" ]
}

@test "get_workflow_agent_config returns workflow-specific agent args as space-separated string" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: pi
      args:
        - --model
        - claude-sonnet-4-5
        - --provider
        - anthropic
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_agent_config "feature" "args")"
    [ "$result" = "--model claude-sonnet-4-5 --provider anthropic" ]
}

@test "get_workflow_agent_config returns workflow-specific agent command" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: custom
      command: my-agent
      template: "{{command}} {{args}} < {{prompt_file}}"
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_agent_config "feature" "command")"
    [ "$result" = "my-agent" ]
}

@test "get_workflow_agent_config returns workflow-specific agent template" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
    agent:
      type: custom
      command: my-agent
      template: "{{command}} {{args}} < {{prompt_file}}"
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_agent_config "feature" "template")"
    [ "$result" = "{{command}} {{args}} < {{prompt_file}}" ]
}

@test "get_workflow_agent_config returns empty string when workflow agent is not configured" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_agent_config "feature" "type")"
    [ "$result" = "" ]
}

@test "get_workflow_agent_config returns empty string when workflow does not exist" {
    reset_yaml_cache
    
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  feature:
    description: Feature workflow
    steps:
      - plan
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(get_workflow_agent_config "nonexistent" "type")"
    [ "$result" = "" ]
}

@test "get_workflow_agent_config returns empty string when config file does not exist" {
    export CONFIG_FILE="$TEST_DIR/nonexistent.yaml"
    
    result="$(get_workflow_agent_config "feature" "type")"
    [ "$result" = "" ]
}

# ========================================
# get_workflow_agent_property テスト（ファイル形式ワークフロー）
# Issue #1135
# ========================================

@test "get_workflow_agent_property returns agent type from workflow YAML file" {
    reset_yaml_cache

    cat > "$TEST_DIR/workflows/frontend.yaml" << 'EOF'
name: frontend
description: Frontend workflow
steps:
  - plan
  - implement
  - review
  - merge
agent:
  type: pi
  args:
    - --model
    - claude-sonnet-4-20250514
EOF

    result="$(get_workflow_agent_property "$TEST_DIR/workflows/frontend.yaml" "type")"
    [ "$result" = "pi" ]
}

@test "get_workflow_agent_property returns agent args from workflow YAML file" {
    reset_yaml_cache

    cat > "$TEST_DIR/workflows/frontend.yaml" << 'EOF'
name: frontend
steps:
  - implement
agent:
  type: pi
  args:
    - --model
    - claude-sonnet-4-20250514
EOF

    result="$(get_workflow_agent_property "$TEST_DIR/workflows/frontend.yaml" "args")"
    [ "$result" = "--model claude-sonnet-4-20250514" ]
}

@test "get_workflow_agent_property returns agent command from workflow YAML file" {
    reset_yaml_cache

    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
agent:
  type: custom
  command: my-agent
  template: "{{command}} {{args}} < {{prompt_file}}"
EOF

    result="$(get_workflow_agent_property "$TEST_DIR/workflows/custom.yaml" "command")"
    [ "$result" = "my-agent" ]
}

@test "get_workflow_agent_property returns agent template from workflow YAML file" {
    reset_yaml_cache

    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
agent:
  type: custom
  command: my-agent
  template: "{{command}} {{args}} < {{prompt_file}}"
EOF

    result="$(get_workflow_agent_property "$TEST_DIR/workflows/custom.yaml" "template")"
    [ "$result" = "{{command}} {{args}} < {{prompt_file}}" ]
}

@test "get_workflow_agent_property returns empty when agent not defined in workflow YAML file" {
    reset_yaml_cache

    cat > "$TEST_DIR/workflows/simple.yaml" << 'EOF'
name: simple
steps:
  - implement
  - merge
EOF

    result="$(get_workflow_agent_property "$TEST_DIR/workflows/simple.yaml" "type")"
    [ "$result" = "" ]
}

@test "get_workflow_agent_property returns empty for nonexistent workflow file" {
    result="$(get_workflow_agent_property "$TEST_DIR/nonexistent.yaml" "type")"
    [ "$result" = "" ]
}

@test "get_workflow_agent_property returns empty for builtin workflow" {
    result="$(get_workflow_agent_property "builtin:default" "type")"
    [ "$result" = "" ]
}

@test "get_workflow_agent_property returns agent type from config-workflow" {
    reset_yaml_cache

    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  feature:
    steps:
      - plan
      - implement
    agent:
      type: claude
EOF

    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"

    result="$(get_workflow_agent_property "config-workflow:feature" "type")"
    [ "$result" = "claude" ]
}

@test "get_workflow_agent_property returns all agent properties from workflow YAML file" {
    reset_yaml_cache

    cat > "$TEST_DIR/workflows/full.yaml" << 'EOF'
name: full
steps:
  - plan
  - implement
  - merge
agent:
  type: custom
  command: my-agent
  args:
    - --verbose
    - --model
    - gpt-4
  template: "{{command}} {{args}} < {{prompt_file}}"
EOF

    type="$(get_workflow_agent_property "$TEST_DIR/workflows/full.yaml" "type")"
    command="$(get_workflow_agent_property "$TEST_DIR/workflows/full.yaml" "command")"
    args="$(get_workflow_agent_property "$TEST_DIR/workflows/full.yaml" "args")"
    template="$(get_workflow_agent_property "$TEST_DIR/workflows/full.yaml" "template")"

    [ "$type" = "custom" ]
    [ "$command" = "my-agent" ]
    [ "$args" = "--verbose --model gpt-4" ]
    [ "$template" = "{{command}} {{args}} < {{prompt_file}}" ]
}

# ===================
# get_workflow_steps_typed
# ===================

@test "get_workflow_steps_typed returns ai steps for builtin workflow" {
    run get_workflow_steps_typed "builtin:default"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ai	plan"* ]]
    [[ "$output" == *"ai	implement"* ]]
    [[ "$output" == *"ai	merge"* ]]
}

@test "get_workflow_steps_typed returns ai steps for simple builtin" {
    run get_workflow_steps_typed "builtin:simple"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ai	implement"* ]]
    [[ "$output" == *"ai	merge"* ]]
}

@test "get_workflow_steps_typed parses run: steps from config" {
    if ! check_yq; then
        skip "yq not available"
    fi
    cat > "$BATS_TEST_TMPDIR/config.yaml" << 'EOF'
workflows:
  test-wf:
    steps:
      - implement
      - run: "shellcheck -x scripts/*.sh"
        timeout: 600
      - merge
EOF
    export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yaml"
    _WORKFLOW_LOADER_SH_SOURCED="" ; source "$PROJECT_ROOT/lib/workflow-loader.sh"

    run get_workflow_steps_typed "config-workflow:test-wf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ai	implement"* ]]
    [[ "$output" == *"run	shellcheck -x scripts/*.sh	600"* ]]
    [[ "$output" == *"ai	merge"* ]]
}

@test "get_workflow_steps_typed ignores deprecated call: steps with warning" {
    if ! check_yq; then
        skip "yq not available"
    fi
    cat > "$BATS_TEST_TMPDIR/config.yaml" << 'EOF'
workflows:
  test-wf:
    steps:
      - implement
      - call: code-review
        timeout: 300
        max_retry: 2
      - merge
EOF
    export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yaml"
    _WORKFLOW_LOADER_SH_SOURCED="" ; source "$PROJECT_ROOT/lib/workflow-loader.sh"

    run get_workflow_steps_typed "config-workflow:test-wf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ai	implement"* ]]
    # call: steps should be ignored (deprecated)
    [[ "$output" != *"call	code-review"* ]]
    [[ "$output" == *"ai	merge"* ]]
}

# ===================
# get_step_groups
# ===================

@test "get_step_groups groups consecutive AI steps" {
    local input
    input=$(printf "ai\tplan\nai\timplement\nai\tmerge\n")
    local result
    result=$(echo "$input" | get_step_groups)
    [[ "$result" == *"ai_group	plan implement merge"* ]]
}

@test "get_step_groups splits on non-AI steps" {
    if ! check_yq; then
        skip "yq not available"
    fi
    cat > "$BATS_TEST_TMPDIR/config.yaml" << 'EOF'
workflows:
  test-wf:
    steps:
      - plan
      - implement
      - run: "shellcheck -x scripts/*.sh"
      - merge
EOF
    export CONFIG_FILE="$BATS_TEST_TMPDIR/config.yaml"
    _WORKFLOW_LOADER_SH_SOURCED="" ; source "$PROJECT_ROOT/lib/workflow-loader.sh"

    local groups
    groups=$(get_workflow_steps_typed "config-workflow:test-wf" | get_step_groups)

    # 3 groups: ai_group, non_ai_group, ai_group
    local count
    count=$(echo "$groups" | wc -l | tr -d ' ')
    [ "$count" -eq 3 ]
    [[ "$(echo "$groups" | sed -n '1p')" == "ai_group	plan implement" ]]
    [[ "$(echo "$groups" | sed -n '2p')" == *"non_ai_group"* ]]
    [[ "$(echo "$groups" | sed -n '3p')" == "ai_group	merge" ]]
}

# ===================
# typed_steps_to_ai_only
# ===================

@test "typed_steps_to_ai_only extracts only AI steps" {
    local input
    input=$(printf "ai\tplan\nrun\tshellcheck\t300\t0\t10\tfalse\tshellcheck\nai\tmerge\n")
    result=$(echo "$input" | typed_steps_to_ai_only)
    [ "$result" = "plan merge" ]
}
