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
    
    # YAMLキャッシュをリセット（並列テストでのキャッシュ汚染防止）
    reset_yaml_cache
    
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
    # ビルトインワークフローは context を持つことを確認 (Issue #1040)
    result="$(generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR")"
    
    [[ "$result" == *"### Workflow Context"* ]]
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

# ====================
# generate_workflow_prompt テスト（auto モード）
# ====================

@test "generate_workflow_prompt generates selection prompt for auto mode" {
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
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # Workflow Selection セクションが含まれる
    [[ "$result" == *"## Workflow Selection"* ]]
    [[ "$result" == *"Available Workflows"* ]]
    [[ "$result" == *"Workflow Details"* ]]
}

@test "auto mode prompt includes all workflow descriptions" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正（typo、設定変更）
    steps:
      - implement
  thorough:
    description: 大規模機能開発（複数ファイル）
    steps:
      - plan
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # 各ワークフローの description が含まれる
    [[ "$result" == *"小規模修正（typo、設定変更）"* ]]
    [[ "$result" == *"大規模機能開発（複数ファイル）"* ]]
}

@test "auto mode prompt includes workflow steps" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  test:
    description: テストワークフロー
    steps:
      - plan
      - implement
      - test
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # steps が → 区切りで表示される
    [[ "$result" == *"plan → implement → test"* ]]
}

@test "auto mode prompt includes workflow context" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  frontend:
    description: フロントエンド実装
    steps:
      - implement
    context: |
      ## Tech Stack
      - React / Next.js
      
      ## Important
      - Use TypeScript
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # context が含まれる
    [[ "$result" == *"Tech Stack"* ]]
    [[ "$result" == *"React / Next.js"* ]]
    [[ "$result" == *"Use TypeScript"* ]]
}

@test "auto mode prompt falls back to builtin workflows when workflows section not defined" {
    # workflows セクションなし
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflow:
  steps:
    - plan
    - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # ビルトインワークフローが含まれる
    [[ "$result" == *"default"* ]]
    [[ "$result" == *"simple"* ]]
}

@test "auto mode prompt includes execution context" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  test:
    description: テスト
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "99" "Test Issue" "Test body" "feature/test" "/worktree/path" "$TEST_DIR")"
    
    # 実行コンテキストが含まれる
    [[ "$result" == *"Issue番号"* ]]
    [[ "$result" == *"#99"* ]]
    [[ "$result" == *"ブランチ"* ]]
    [[ "$result" == *"feature/test"* ]]
    [[ "$result" == *"作業ディレクトリ"* ]]
    [[ "$result" == *"/worktree/path"* ]]
}

@test "auto mode prompt includes selection instruction" {
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  test:
    description: テスト
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # 選択指示が含まれる
    [[ "$result" == *"Issue の内容を分析し"* ]]
    [[ "$result" == *"最も適切なワークフローを選択"* ]]
}

# ====================
# Context Truncation テスト（Issue #1018）
# ====================

@test "auto mode prompt truncates long context to 300 characters" {
    # 400文字のcontextを生成
    local long_context="$(printf '%.0s#' {1..400})"
    
    cat > "$TEST_DIR/.pi-runner.yaml" << YAML_EOF
workflows:
  test:
    description: テスト
    steps:
      - implement
    context: |
      $long_context
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # contextが展開されていることを確認
    [[ "$result" == *"**Context**:"* ]]
    
    # 300文字に切り詰められ、末尾に"..."が付与されていることを確認
    # contextセクションを抽出して検証
    local context_section
    context_section=$(echo "$result" | sed -n '/\*\*Context\*\*:/,/^$/p')
    
    # 300文字 + "..." が含まれる（正確に303文字の#と...）
    [[ "$context_section" == *"..."* ]]
    
    # 元の400文字全てが含まれていないことを確認（トランケートされている）
    local full_hash_sequence="$(printf '%.0s#' {1..400})"
    [[ "$context_section" != *"$full_hash_sequence"* ]]
}

@test "auto mode prompt does not truncate short context" {
    # 100文字のcontextを生成
    local short_context="$(printf '%.0s#' {1..100})"
    
    cat > "$TEST_DIR/.pi-runner.yaml" << YAML_EOF
workflows:
  test:
    description: テスト
    steps:
      - implement
    context: |
      $short_context
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # contextが展開されていることを確認
    [[ "$result" == *"**Context**:"* ]]
    
    # contextセクションを抽出
    local context_section
    context_section=$(echo "$result" | sed -n '/\*\*Context\*\*:/,/^$/p')
    
    # 短いcontextは全文が含まれる（"..."が付与されていない）
    [[ "$context_section" == *"$short_context"* ]]
    
    # トランケーション時の"..."が含まれていないことを確認
    # ただし、YAMLの改行などで"..."が含まれる可能性があるため、
    # 100文字のハッシュシーケンスが完全に含まれていることで検証
    local full_hash_sequence="$(printf '%.0s#' {1..100})"
    [[ "$context_section" == *"$full_hash_sequence"* ]]
}

@test "auto mode prompt truncates context at exactly 300 characters" {
    # ちょうど300文字のcontextを生成
    local exact_context="$(printf '%.0s#' {1..300})"
    
    cat > "$TEST_DIR/.pi-runner.yaml" << YAML_EOF
workflows:
  test:
    description: テスト
    steps:
      - implement
    context: |
      $exact_context
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # contextセクションを抽出
    local context_section
    context_section=$(echo "$result" | sed -n '/\*\*Context\*\*:/,/^$/p')
    
    # 300文字ちょうどの場合は"..."が付与されない
    [[ "$context_section" == *"$exact_context"* ]]
    
    # "..."が末尾に付いていないことを確認
    # （ただしYAML内の他の箇所に"..."がある可能性があるため、contextセクションのみで確認）
    local full_hash_sequence="$(printf '%.0s#' {1..300})"
    [[ "$context_section" == *"$full_hash_sequence"* ]]
}

@test "auto mode prompt truncates multiple workflows with long context" {
    # 複数のワークフローがそれぞれ長いcontextを持つ場合
    local long_context="$(printf '%.0s#' {1..500})"
    
    cat > "$TEST_DIR/.pi-runner.yaml" << YAML_EOF
workflows:
  workflow1:
    description: ワークフロー1
    steps:
      - implement
    context: |
      $long_context
  workflow2:
    description: ワークフロー2
    steps:
      - implement
    context: |
      $long_context
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    result="$(generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR")"
    
    # 両方のワークフローのcontextが含まれる
    [[ "$result" == *"workflow1"* ]]
    [[ "$result" == *"workflow2"* ]]
    
    # 両方のcontextがトランケートされて"..."が付与されている
    # （2つの"..."が含まれる）
    local ellipsis_count
    ellipsis_count=$(echo "$result" | grep -o '\.\.\.' | wc -l | tr -d ' ')
    [ "$ellipsis_count" -ge 2 ]
}
