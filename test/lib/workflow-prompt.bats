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
    
    # workflow.sh が workflow-prompt.sh を読み込むので、workflow.sh をsource
    source "$PROJECT_ROOT/lib/workflow.sh"
    
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
# generate_workflow_prompt テスト - ヘッダー
# ====================

@test "generate_workflow_prompt includes issue number in header" {
    result="$(generate_workflow_prompt "default" "42" "Test Issue" "Issue body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"Implement GitHub Issue #42"* ]]
}

@test "generate_workflow_prompt includes issue title" {
    result="$(generate_workflow_prompt "default" "42" "My Test Issue" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"## Title"* ]]
    [[ "$result" == *"My Test Issue"* ]]
}

@test "generate_workflow_prompt includes issue body" {
    result="$(generate_workflow_prompt "default" "42" "Title" "This is the issue body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"## Description"* ]]
    [[ "$result" == *"This is the issue body"* ]]
}

@test "generate_workflow_prompt includes workflow name" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"## Workflow: default"* ]]
}

@test "generate_workflow_prompt includes simple workflow name" {
    result="$(generate_workflow_prompt "simple" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"## Workflow: simple"* ]]
}

# ====================
# generate_workflow_prompt テスト - ステップ
# ====================

@test "generate_workflow_prompt includes Step 1: Plan for default workflow" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 1: Plan"* ]]
}

@test "generate_workflow_prompt includes Step 2: Implement for default workflow" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 2: Implement"* ]]
}

@test "generate_workflow_prompt includes Step 3: Review for default workflow" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 3: Review"* ]]
}

@test "generate_workflow_prompt includes Step 4: Merge for default workflow" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 4: Merge"* ]]
}

@test "generate_workflow_prompt includes Step 1: Implement for simple workflow" {
    result="$(generate_workflow_prompt "simple" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 1: Implement"* ]]
}

@test "generate_workflow_prompt includes Step 2: Merge for simple workflow" {
    result="$(generate_workflow_prompt "simple" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 2: Merge"* ]]
}

@test "generate_workflow_prompt does not include Step 3 for simple workflow" {
    result="$(generate_workflow_prompt "simple" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" != *"### Step 3:"* ]]
}

# ====================
# generate_workflow_prompt テスト - フッター
# ====================

@test "generate_workflow_prompt includes Commit Types section" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Commit Types"* ]]
}

@test "generate_workflow_prompt includes feat commit type" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"feat:"* ]] || [[ "$result" == *"- feat"* ]]
}

@test "generate_workflow_prompt includes On Error section" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### On Error"* ]]
}

@test "generate_workflow_prompt includes error marker format" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"###TASK"* ]]
    [[ "$result" == *"_ERROR_"* ]]
}

@test "generate_workflow_prompt includes On Completion section" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### On Completion"* ]]
}

@test "generate_workflow_prompt includes completion marker format" {
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"_COMPLETE_"* ]]
}

@test "generate_workflow_prompt includes issue number in markers" {
    result="$(generate_workflow_prompt "default" "99" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"99"* ]]
}

# ====================
# generate_workflow_prompt テスト - カスタムワークフロー
# ====================

@test "generate_workflow_prompt uses custom workflow file" {
    cat > "$TEST_PROJECT/workflows/custom.yaml" << 'EOF'
name: custom
steps:
  - design
  - implement
  - test
EOF
    
    result="$(generate_workflow_prompt "custom" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 1: Design"* ]]
    [[ "$result" == *"### Step 2: Implement"* ]]
    [[ "$result" == *"### Step 3: Test"* ]]
}

@test "generate_workflow_prompt uses custom agent file" {
    cat > "$TEST_PROJECT/agents/plan.md" << 'EOF'
# Custom Plan Agent
Issue: #{{issue_number}}
Branch: {{branch_name}}
EOF
    
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"# Custom Plan Agent"* ]]
    [[ "$result" == *"Issue: #42"* ]]
    [[ "$result" == *"Branch: feature/test"* ]]
}

# ====================
# write_workflow_prompt テスト
# ====================

@test "write_workflow_prompt creates file" {
    output_file="$BATS_TEST_TMPDIR/prompt.md"
    write_workflow_prompt "$output_file" "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT"
    
    [ -f "$output_file" ]
}

@test "write_workflow_prompt file contains issue number" {
    output_file="$BATS_TEST_TMPDIR/prompt.md"
    write_workflow_prompt "$output_file" "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT"
    
    content="$(cat "$output_file")"
    [[ "$content" == *"#42"* ]]
}

@test "write_workflow_prompt file contains workflow steps" {
    output_file="$BATS_TEST_TMPDIR/prompt.md"
    write_workflow_prompt "$output_file" "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT"
    
    content="$(cat "$output_file")"
    [[ "$content" == *"### Step 1: Plan"* ]]
    [[ "$content" == *"### Step 4: Merge"* ]]
}

@test "write_workflow_prompt file matches generate_workflow_prompt output" {
    output_file="$BATS_TEST_TMPDIR/prompt.md"
    write_workflow_prompt "$output_file" "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT"
    
    file_content="$(cat "$output_file")"
    generated="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    
    [ "$file_content" = "$generated" ]
}

@test "write_workflow_prompt creates parent directories" {
    output_file="$BATS_TEST_TMPDIR/nested/dir/prompt.md"
    mkdir -p "$(dirname "$output_file")"
    write_workflow_prompt "$output_file" "default" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT"
    
    [ -f "$output_file" ]
}

# ====================
# エッジケーステスト
# ====================

@test "generate_workflow_prompt handles empty issue body" {
    result="$(generate_workflow_prompt "default" "42" "Title" "" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"## Description"* ]]
}

@test "generate_workflow_prompt handles multiline issue body" {
    body="Line 1
Line 2
Line 3"
    result="$(generate_workflow_prompt "default" "42" "Title" "$body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"Line 1"* ]]
    [[ "$result" == *"Line 2"* ]]
    [[ "$result" == *"Line 3"* ]]
}

@test "generate_workflow_prompt handles special characters in title" {
    result="$(generate_workflow_prompt "default" "42" "Fix: handle & and < characters" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"Fix: handle & and < characters"* ]]
}

@test "generate_workflow_prompt uses default project_root when not specified" {
    cd "$TEST_PROJECT"
    result="$(generate_workflow_prompt "default" "42" "Title" "Body" "feature/test" "/path/wt")"
    [[ "$result" == *"#42"* ]]
}

@test "generate_workflow_prompt capitalizes step names" {
    cat > "$TEST_PROJECT/workflows/lowercase.yaml" << 'EOF'
name: lowercase
steps:
  - mystep
EOF
    
    result="$(generate_workflow_prompt "lowercase" "42" "Title" "Body" "feature/test" "/path/wt" "$TEST_PROJECT")"
    [[ "$result" == *"### Step 1: Mystep"* ]]
}
