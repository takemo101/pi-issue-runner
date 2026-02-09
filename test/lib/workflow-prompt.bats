#!/usr/bin/env bats
# workflow-prompt.sh のBatsテスト
#
# Performance optimization: generate_workflow_prompt takes ~5s per call
# (YAML parsing, template rendering for multiple agents).
# Tests are grouped by prompt parameters and share cached results
# to minimize the number of generate_workflow_prompt calls.
#
# In BATS_FAST_MODE, most tests are skipped since each call is expensive.

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # yqキャッシュをリセット
    _YQ_CHECK_RESULT=""
    
    # workflow-prompt.sh は workflow.sh 経由でロードする必要がある
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

# Skip helper for slow tests (each generate_workflow_prompt call takes ~5s)
_skip_in_fast_mode() {
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
}

# ====================
# generate_workflow_prompt テスト（ヘッダー・ステップ・フッター）
# 同一パラメータのテストをまとめて1回のgenerate_workflow_prompt呼び出しで検証
# ====================

@test "generate_workflow_prompt default: includes header, steps, and footer sections" {
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "42" "Test Issue" "Test body" "feature/test" "/path" "$TEST_DIR" > "$result_file"
    
    # ヘッダー
    grep -qF "Implement GitHub Issue #42" "$result_file"
    grep -qF "## Title" "$result_file"
    grep -qF "Test Issue" "$result_file"
    grep -qF "## Description" "$result_file"
    grep -qF "Test body" "$result_file"
    grep -qF "## Workflow: default" "$result_file"
    grep -qF "implementing GitHub Issue #42 in an isolated worktree" "$result_file"
    
    # ステップ
    grep -qF "### Step 1: Plan" "$result_file"
    grep -qF "### Step 2: Implement" "$result_file"
    grep -qF "### Step 3: Review" "$result_file"
    grep -qF "### Step 4: Merge" "$result_file"
    
    # フッター
    grep -qF "### Commit Types" "$result_file"
    grep -qF "feat: New feature" "$result_file"
    grep -qF "fix: Bug fix" "$result_file"
    grep -qF "test: Adding tests" "$result_file"
    grep -qF "### On Error" "$result_file"
    grep -qF "### On Completion" "$result_file"
    
    # マーカー
    grep -qF '###TASK' "$result_file"
    grep -qF '_ERROR_' "$result_file"
    grep -qF '_COMPLETE_' "$result_file"
    grep -qF "unrecoverable errors" "$result_file"
    
    # Workflow Context（ビルトインdefaultにもcontextがある - Issue #1040）
    grep -qF "### Workflow Context" "$result_file"
}

@test "generate_workflow_prompt default: has correct section order" {
    _skip_in_fast_mode
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    local result
    result="$(cat "$result_file")"
    
    # Title comes before Description
    title_pos="${result%%## Title*}"
    desc_pos="${result%%## Description*}"
    [ ${#title_pos} -lt ${#desc_pos} ]
    
    # Description comes before Workflow
    workflow_pos="${result%%## Workflow:*}"
    [ ${#desc_pos} -lt ${#workflow_pos} ]
    
    # Has --- separator
    grep -qF "---" "$result_file"
}

@test "generate_workflow_prompt simple has only 2 steps" {
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "simple" "1" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "### Step 1: Implement" "$result_file"
    grep -qF "### Step 2: Merge" "$result_file"
    # Should not have Step 3
    ! grep -qF "### Step 3:" "$result_file"
}

@test "generate_workflow_prompt includes issue number 99 in markers" {
    _skip_in_fast_mode
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "99" "My Test Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "99" "$result_file"
    grep -qF "My Test Title" "$result_file"
}

# ====================
# generate_workflow_prompt テスト（カスタムワークフロー）
# ====================

@test "generate_workflow_prompt uses custom workflow from YAML" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
  - test
  - merge
EOF
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "custom" "1" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "### Step 1: Implement" "$result_file"
    grep -qF "### Step 2: Test" "$result_file"
    grep -qF "### Step 3: Merge" "$result_file"
}

@test "generate_workflow_prompt uses custom agent templates" {
    _skip_in_fast_mode
    echo "Custom plan for #{{issue_number}} - {{issue_title}}" > "$TEST_DIR/agents/plan.md"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "42" "My Issue" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "Custom plan for #42 - My Issue" "$result_file"
}

# ====================
# write_workflow_prompt テスト
# ====================

@test "write_workflow_prompt creates output file with correct content" {
    output_file="$BATS_TEST_TMPDIR/output.md"
    
    write_workflow_prompt "$output_file" "default" "42" "Test Issue" "Test body" "feature/branch" "/path/worktree" "$TEST_DIR"
    
    [ -f "$output_file" ]
    grep -qF "Implement GitHub Issue #42" "$output_file"
    grep -qF "Test Issue" "$output_file"
    grep -qF "Test body" "$output_file"
}

@test "write_workflow_prompt overwrites existing file" {
    _skip_in_fast_mode
    output_file="$BATS_TEST_TMPDIR/output.md"
    echo "old content" > "$output_file"
    
    write_workflow_prompt "$output_file" "default" "99" "New Title" "New body" "branch" "/path" "$TEST_DIR"
    
    ! grep -qF "old content" "$output_file"
    grep -qF "#99" "$output_file"
}

@test "write_workflow_prompt creates parent directories if needed" {
    _skip_in_fast_mode
    output_file="$BATS_TEST_TMPDIR/nested/dir/output.md"
    mkdir -p "$(dirname "$output_file")"
    
    write_workflow_prompt "$output_file" "default" "1" "Title" "Body" "branch" "/path" "$TEST_DIR"
    
    [ -f "$output_file" ]
}

# ====================
# エッジケーステスト
# ====================

@test "generate_workflow_prompt handles edge cases" {
    _skip_in_fast_mode
    local result_file="$BATS_TEST_TMPDIR/result.md"
    
    # Empty body
    generate_workflow_prompt "default" "1" "Title" "" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "## Description" "$result_file"
    
    # Special characters in title
    generate_workflow_prompt "default" "1" "Fix: bug (issue-1) @test" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "Fix: bug (issue-1) @test" "$result_file"
    
    # Long issue number
    generate_workflow_prompt "default" "999999" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "#999999" "$result_file"
}

@test "generate_workflow_prompt handles multiline issue body" {
    _skip_in_fast_mode
    local body
    body="$(printf 'Line 1\nLine 2\nLine 3')"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "1" "Title" "$body" "branch" "/path" "$TEST_DIR" > "$result_file"
    grep -qF "Line 1" "$result_file"
    grep -qF "Line 2" "$result_file"
    grep -qF "Line 3" "$result_file"
}

@test "generate_workflow_prompt handles branch name with slashes" {
    _skip_in_fast_mode
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "1" "Title" "Body" "feature/deep/nested/branch" "/path" "$TEST_DIR" > "$result_file"
    [ -s "$result_file" ]
}

@test "generate_workflow_prompt handles worktree path with spaces" {
    _skip_in_fast_mode
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path/with spaces/dir" "$TEST_DIR" > "$result_file"
    [ -s "$result_file" ]
}

@test "generate_workflow_prompt uses current directory as default project_root" {
    _skip_in_fast_mode
    cd "$TEST_DIR"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "default" "1" "Title" "Body" "branch" "/path" > "$result_file"
    grep -qF "Step 1: Plan" "$result_file"
}

# ====================
# generate_workflow_prompt テスト（コンテキスト注入）- Issue #914
# ====================

@test "generate_workflow_prompt includes Workflow Context with all details when context defined" {
    _skip_in_fast_mode
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "frontend" "42" "Test Issue" "Test body" "feature/test" "/path" "$TEST_DIR" > "$result_file"
    
    grep -qF "### Workflow Context" "$result_file"
    grep -qF "技術スタック" "$result_file"
    grep -qF "React / Next.js / TypeScript" "$result_file"
    grep -qF "重視すべき点" "$result_file"
    grep -qF "レスポンシブデザイン" "$result_file"
    grep -qF "アクセシビリティ" "$result_file"
}

@test "generate_workflow_prompt omits Workflow Context section when no context defined" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/.pi-runner.yaml" << 'EOF'
workflows:
  quick:
    description: "Quick fix workflow"
    steps:
      - implement
      - merge
EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "quick" "42" "Test Issue" "Test body" "feature/test" "/path" "$TEST_DIR" > "$result_file"
    
    ! grep -qF "### Workflow Context" "$result_file"
}

@test "generate_workflow_prompt context appears before steps with separator" {
    _skip_in_fast_mode
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "backend" "1" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    local result
    result="$(cat "$result_file")"
    
    # コンテキストがステップより前に出現することを確認
    context_pos="${result%%### Workflow Context*}"
    step_pos="${result%%### Step 1:*}"
    [ ${#context_pos} -lt ${#step_pos} ]
    
    # Context と Step の間に --- がある
    context_section="${result#*### Workflow Context}"
    context_section="${context_section%%### Step 1:*}"
    [[ "$context_section" == *"---"* ]]
}

@test "generate_workflow_prompt handles context with code blocks" {
    _skip_in_fast_mode
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "infra" "1" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    grep -qF "### Workflow Context" "$result_file"
    grep -qF "Tech Stack" "$result_file"
    grep -qF "Terraform" "$result_file"
    grep -qF '```terraform' "$result_file"
    grep -qF 'resource "aws_instance"' "$result_file"
}

@test "generate_workflow_prompt context works with file-based workflows" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - implement
  - merge
context: |
  ## File-based Context
  - Custom context from YAML file
EOF
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "custom" "1" "Title" "Body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    grep -qF "### Workflow Context" "$result_file"
    grep -qF "File-based Context" "$result_file"
    grep -qF "Custom context from YAML file" "$result_file"
}

# ====================
# generate_workflow_prompt テスト（auto モード）
# ====================

@test "generate_workflow_prompt auto mode: generates selection prompt with workflows" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  quick:
    description: 小規模修正（typo、設定変更）
    steps:
      - implement
      - merge
  thorough:
    description: 大規模機能開発（複数ファイル）
    steps:
      - plan
      - implement
      - test
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # Workflow Selection セクション
    grep -qF "## Workflow Selection" "$result_file"
    grep -qF "Available Workflows" "$result_file"
    grep -qF "Workflow Details" "$result_file"
    
    # 各ワークフローの description
    grep -qF "小規模修正（typo、設定変更）" "$result_file"
    grep -qF "大規模機能開発（複数ファイル）" "$result_file"
}

@test "auto mode prompt includes workflow steps and context" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  frontend:
    description: フロントエンド実装
    steps:
      - plan
      - implement
      - test
    context: |
      ## Tech Stack
      - React / Next.js
      
      ## Important
      - Use TypeScript
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # steps が → 区切りで表示される
    grep -qF "plan → implement → test" "$result_file" || grep -qF "plan" "$result_file"
    
    # context が含まれる
    grep -qF "Tech Stack" "$result_file"
    grep -qF "React / Next.js" "$result_file"
    grep -qF "Use TypeScript" "$result_file"
}

@test "auto mode prompt falls back to builtin workflows when workflows section not defined" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflow:
  steps:
    - plan
    - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # ビルトインワークフローが含まれる
    grep -qF "default" "$result_file"
    grep -qF "simple" "$result_file"
}

@test "auto mode prompt includes execution context and selection instruction" {
    _skip_in_fast_mode
    cat > "$TEST_DIR/.pi-runner.yaml" << 'YAML_EOF'
workflows:
  test:
    description: テスト
    steps:
      - implement
YAML_EOF
    
    export CONFIG_FILE="$TEST_DIR/.pi-runner.yaml"
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "99" "Test Issue" "Test body" "feature/test" "/worktree/path" "$TEST_DIR" > "$result_file"
    
    # 実行コンテキスト
    grep -qF "Issue番号" "$result_file"
    grep -qF "#99" "$result_file"
    grep -qF "ブランチ" "$result_file"
    grep -qF "feature/test" "$result_file"
    grep -qF "作業ディレクトリ" "$result_file"
    grep -qF "/worktree/path" "$result_file"
    
    # 選択指示
    grep -qF "Issue の内容を分析し" "$result_file"
    grep -qF "最も適切なワークフローを選択" "$result_file"
}

# ====================
# Context Truncation テスト（Issue #1018）
# ====================

@test "auto mode prompt truncates long context to 300 characters" {
    _skip_in_fast_mode
    # 400文字のcontextを生成
    local long_context
    long_context="$(printf '%.0s#' {1..400})"
    
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # contextが展開されていることを確認
    grep -qF "**Context**:" "$result_file"
    
    # contextセクションを抽出して検証
    local context_section
    context_section=$(sed -n '/\*\*Context\*\*:/,/^$/p' "$result_file")
    
    # 300文字に切り詰められ、末尾に"..."が付与されている
    [[ "$context_section" == *"..."* ]]
    
    # 元の400文字全てが含まれていないことを確認（トランケートされている）
    local full_hash_sequence
    full_hash_sequence="$(printf '%.0s#' {1..400})"
    [[ "$context_section" != *"$full_hash_sequence"* ]]
}

@test "auto mode prompt does not truncate short context" {
    _skip_in_fast_mode
    # 100文字のcontextを生成
    local short_context
    short_context="$(printf '%.0s#' {1..100})"
    
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # contextが展開されていることを確認
    grep -qF "**Context**:" "$result_file"
    
    # contextセクションを抽出
    local context_section
    context_section=$(sed -n '/\*\*Context\*\*:/,/^$/p' "$result_file")
    
    # 短いcontextは全文が含まれる
    local full_hash_sequence
    full_hash_sequence="$(printf '%.0s#' {1..100})"
    [[ "$context_section" == *"$full_hash_sequence"* ]]
}

@test "auto mode prompt truncates context at exactly 300 characters" {
    _skip_in_fast_mode
    # ちょうど300文字のcontextを生成
    local exact_context
    exact_context="$(printf '%.0s#' {1..300})"
    
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # contextセクションを抽出
    local context_section
    context_section=$(sed -n '/\*\*Context\*\*:/,/^$/p' "$result_file")
    
    # 300文字ちょうどの場合は全文が含まれる
    [[ "$context_section" == *"$exact_context"* ]]
}

@test "auto mode prompt truncates multiple workflows with long context" {
    _skip_in_fast_mode
    # 複数のワークフローがそれぞれ長いcontextを持つ場合
    local long_context
    long_context="$(printf '%.0s#' {1..500})"
    
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
    
    local result_file="$BATS_TEST_TMPDIR/result.md"
    generate_workflow_prompt "auto" "42" "Test Issue" "Test body" "branch" "/path" "$TEST_DIR" > "$result_file"
    
    # 両方のワークフローのcontextが含まれる
    grep -qF "workflow1" "$result_file"
    grep -qF "workflow2" "$result_file"
    
    # 両方のcontextがトランケートされて"..."が付与されている
    local ellipsis_count
    ellipsis_count=$(grep -o '\.\.\.' "$result_file" | wc -l | tr -d ' ')
    [ "$ellipsis_count" -ge 2 ]
}
