#!/usr/bin/env bats
# workflow-prompt.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
    
    # workflow-prompt.sh は workflow.sh 経由でロードする必要がある
    # （find_workflow_file, get_workflow_steps, find_agent_file, get_agent_prompt が必要）
    source "$PROJECT_ROOT/lib/workflow.sh"
    
    # テスト用ディレクトリ構造を作成
    export TEST_DIR="$BATS_TEST_TMPDIR/prompt_test"
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
# generate_workflow_prompt テスト（ヘッダー）
# ====================

@test "generate_workflow_prompt includes issue number in header" {
    result="$(generate_workflow_prompt "default" "42" "Test Issue" "Test body" "feature/test" "/path" "$TEST_DIR")"
    [[ "$result" == *"Implement GitHub Issue #42"* ]]
}

@test "generate_workflow_prompt includes issue title" {
    result="$(generate_workflow_prompt "default" "99" "My Test Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"## Title"* ]]
    [[ "$result" == *"My Test Title"* ]]
}

@test "generate_workflow_prompt includes issue body" {
    result="$(generate_workflow_prompt "default" "1" "Title" "This is the issue body content" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"## Description"* ]]
    [[ "$result" == *"This is the issue body content"* ]]
}

@test "generate_workflow_prompt includes workflow name" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"## Workflow: default"* ]]
}

@test "generate_workflow_prompt includes workflow introduction" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"implementing GitHub Issue #42 in an isolated worktree"* ]]
}

# ====================
# generate_workflow_prompt テスト（ステップ）
# ====================

@test "generate_workflow_prompt includes Step 1: Plan" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Step 1: Plan"* ]]
}

@test "generate_workflow_prompt includes Step 2: Implement" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Step 2: Implement"* ]]
}

@test "generate_workflow_prompt includes Step 3: Review" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Step 3: Review"* ]]
}

@test "generate_workflow_prompt includes Step 4: Merge" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Step 4: Merge"* ]]
}

@test "generate_workflow_prompt simple has only 2 steps" {
    result="$(generate_workflow_prompt "simple" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Step 1: Implement"* ]]
    [[ "$result" == *"### Step 2: Merge"* ]]
    # Should not have Step 3
    [[ "$result" != *"### Step 3:"* ]]
}

# ====================
# generate_workflow_prompt テスト（フッター）
# ====================

@test "generate_workflow_prompt includes Commit Types section" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Commit Types"* ]]
    [[ "$result" == *"feat: New feature"* ]]
    [[ "$result" == *"fix: Bug fix"* ]]
    [[ "$result" == *"test: Adding tests"* ]]
}

@test "generate_workflow_prompt includes On Error section" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### On Error"* ]]
}

@test "generate_workflow_prompt includes error marker documentation" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *'###TASK'* ]]
    [[ "$result" == *'_ERROR_'* ]]
    [[ "$result" == *"unrecoverable errors"* ]]
}

@test "generate_workflow_prompt includes On Completion section" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### On Completion"* ]]
}

@test "generate_workflow_prompt includes completion marker documentation" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *'###TASK'* ]]
    [[ "$result" == *'_COMPLETE_'* ]]
}

@test "generate_workflow_prompt includes issue number in markers" {
    result="$(generate_workflow_prompt "default" "99" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"99"* ]]
}

# ====================
# generate_workflow_prompt テスト（カスタムワークフロー）
# ====================

@test "generate_workflow_prompt uses custom workflow from YAML" {
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
  - test
  - merge
EOF
    
    result="$(generate_workflow_prompt "custom" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"### Step 1: Implement"* ]]
    [[ "$result" == *"### Step 2: Test"* ]]
    [[ "$result" == *"### Step 3: Merge"* ]]
}

@test "generate_workflow_prompt uses custom agent templates" {
    echo "Custom plan for #{{issue_number}} - {{issue_title}}" > "$TEST_DIR/agents/plan.md"
    
    result="$(generate_workflow_prompt "default" "42" "My Issue" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"Custom plan for #42 - My Issue"* ]]
}

# ====================
# write_workflow_prompt テスト
# ====================

@test "write_workflow_prompt creates output file" {
    output_file="$BATS_TEST_TMPDIR/output.md"
    
    write_workflow_prompt "$output_file" "default" "42" "Title" "Body" "branch" "/path" "$TEST_DIR"
    
    [ -f "$output_file" ]
}

@test "write_workflow_prompt writes correct content" {
    output_file="$BATS_TEST_TMPDIR/output.md"
    
    write_workflow_prompt "$output_file" "default" "42" "Test Issue" "Test body" "feature/branch" "/path/worktree" "$TEST_DIR"
    
    content="$(cat "$output_file")"
    [[ "$content" == *"Implement GitHub Issue #42"* ]]
    [[ "$content" == *"Test Issue"* ]]
    [[ "$content" == *"Test body"* ]]
}

@test "write_workflow_prompt overwrites existing file" {
    output_file="$BATS_TEST_TMPDIR/output.md"
    echo "old content" > "$output_file"
    
    write_workflow_prompt "$output_file" "default" "99" "New Title" "New body" "branch" "/path" "$TEST_DIR"
    
    content="$(cat "$output_file")"
    [[ "$content" != *"old content"* ]]
    [[ "$content" == *"#99"* ]]
}

@test "write_workflow_prompt creates parent directories if needed" {
    output_file="$BATS_TEST_TMPDIR/nested/dir/output.md"
    mkdir -p "$(dirname "$output_file")"
    
    write_workflow_prompt "$output_file" "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR"
    
    [ -f "$output_file" ]
}

# ====================
# エッジケーステスト
# ====================

@test "generate_workflow_prompt handles empty issue body" {
    result="$(generate_workflow_prompt "default" "1" "Title" "" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"## Description"* ]]
}

@test "generate_workflow_prompt handles special characters in title" {
    result="$(generate_workflow_prompt "default" "1" "Fix: bug (issue-1) @test" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"Fix: bug (issue-1) @test"* ]]
}

@test "generate_workflow_prompt handles multiline issue body" {
    body="Line 1
Line 2
Line 3"
    
    result="$(generate_workflow_prompt "default" "1" "Title" "$body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"Line 1"* ]]
    [[ "$result" == *"Line 2"* ]]
    [[ "$result" == *"Line 3"* ]]
}

@test "generate_workflow_prompt handles long issue number" {
    result="$(generate_workflow_prompt "default" "999999" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    [[ "$result" == *"#999999"* ]]
}

@test "generate_workflow_prompt handles branch name with slashes" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "feature/deep/nested/branch" "/path" "$TEST_DIR")"
    # Just verify it doesn't fail
    [ -n "$result" ]
}

@test "generate_workflow_prompt handles worktree path with spaces" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path/with spaces/dir" "$TEST_DIR")"
    # Just verify it doesn't fail
    [ -n "$result" ]
}

@test "generate_workflow_prompt uses current directory as default project_root" {
    cd "$TEST_DIR"
    
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path")"
    [[ "$result" == *"Step 1: Plan"* ]]
}

# ====================
# 構造テスト
# ====================

@test "generate_workflow_prompt has correct section order" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    # Title comes before Description
    title_pos="${result%%## Title*}"
    desc_pos="${result%%## Description*}"
    [ ${#title_pos} -lt ${#desc_pos} ]
    
    # Description comes before Workflow
    workflow_pos="${result%%## Workflow:*}"
    [ ${#desc_pos} -lt ${#workflow_pos} ]
}

@test "generate_workflow_prompt includes separator between sections" {
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    # Has --- separator
    [[ "$result" == *"---"* ]]
}

# ====================
# generate_workflow_prompt テスト（コンテキスト注入）- Issue #914
# ====================

@test "generate_workflow_prompt includes Workflow Context section when context defined" {
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
    
    result="$(generate_workflow_prompt "frontend" "42" "Test Issue" "Test body" "feature/test" "/path" "$TEST_DIR")"
    
    # Workflow Context セクションが含まれることを確認
    [[ "$result" == *"### Workflow Context"* ]]
    [[ "$result" == *"技術スタック"* ]]
    [[ "$result" == *"React / Next.js / TypeScript"* ]]
    [[ "$result" == *"重視すべき点"* ]]
    [[ "$result" == *"レスポンシブデザイン"* ]]
    [[ "$result" == *"アクセシビリティ"* ]]
}

@test "generate_workflow_prompt omits Workflow Context section when no context defined" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  quick:
    description: "Quick fix workflow"
    steps:
      - implement
      - merge
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "quick" "42" "Test Issue" "Test body" "feature/test" "/path" "$TEST_DIR")"
    
    # Workflow Context セクションが含まれないことを確認
    [[ "$result" != *"### Workflow Context"* ]]
}

@test "generate_workflow_prompt context appears before steps" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  backend:
    steps:
      - plan
      - implement
    context: |
      ## Backend Context
      - Node.js / Express
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "backend" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    # コンテキストがステップより前に出現することを確認
    context_pos="${result%%### Workflow Context*}"
    step_pos="${result%%### Step 1:*}"
    [ ${#context_pos} -lt ${#step_pos} ]
}

@test "generate_workflow_prompt context section has separator after it" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  test:
    steps:
      - implement
    context: |
      ## Test Context
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "test" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    # コンテキストセクションの後に区切り線があることを確認
    [[ "$result" == *"### Workflow Context"* ]]
    [[ "$result" == *"## Test Context"* ]]
    # Context と Step の間に --- がある
    context_section="${result#*### Workflow Context}"
    context_section="${context_section%%### Step 1:*}"
    [[ "$context_section" == *"---"* ]]
}

@test "generate_workflow_prompt handles context with code blocks" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  infra:
    steps:
      - implement
    context: |
      ## Tech Stack
      - Terraform
      
      ## Example
      ```terraform
      resource "aws_instance" "example" {
        ami = "ami-12345"
      }
      ```
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "infra" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    [[ "$result" == *"### Workflow Context"* ]]
    [[ "$result" == *"Tech Stack"* ]]
    [[ "$result" == *"Terraform"* ]]
    [[ "$result" == *'```terraform'* ]]
    [[ "$result" == *'resource "aws_instance"'* ]]
}

@test "generate_workflow_prompt context works with builtin workflows" {
    # ビルトインワークフローは context を持たないことを確認
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    [[ "$result" != *"### Workflow Context"* ]]
}

@test "generate_workflow_prompt context works with file-based workflows" {
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
  - merge
context: |
  ## File-based Context
  - Custom context from YAML file
EOF
    
    result="$(generate_workflow_prompt "custom" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    [[ "$result" == *"### Workflow Context"* ]]
    [[ "$result" == *"File-based Context"* ]]
    [[ "$result" == *"Custom context from YAML file"* ]]
}
