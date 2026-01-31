#!/usr/bin/env bash
# workflow.sh のテスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/workflow.sh"

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

# テスト用一時ディレクトリ
TEST_DIR=""

assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_contains() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected to contain: '$expected'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_not_empty() {
    local description="$1"
    local actual="$2"
    if [[ -n "$actual" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (value is empty)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_file_exists() {
    local description="$1"
    local file_path="$2"
    if [[ -f "$file_path" ]] || [[ "$file_path" == builtin:* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (file not found: $file_path)"
        ((TESTS_FAILED++)) || true
    fi
}

# テスト用ディレクトリのセットアップ
setup_test_dir() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/workflows"
    mkdir -p "$TEST_DIR/agents"
    mkdir -p "$TEST_DIR/.pi/agents"
}

# テスト用ディレクトリのクリーンアップ
cleanup_test_dir() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# テスト終了時にクリーンアップ
trap cleanup_test_dir EXIT

# ===================
# check_yq テスト
# ===================
echo "=== check_yq tests ==="

if command -v yq &>/dev/null; then
    check_yq
    assert_equals "check_yq returns 0 when yq is available" "0" "$?"
else
    ! check_yq
    assert_equals "check_yq returns 1 when yq is not available" "0" "$?"
fi

# キャッシュのテスト
# キャッシュをリセット
_YQ_CHECK_RESULT=""

# 1回目の呼び出し
check_yq || true
cache_after_first="$_YQ_CHECK_RESULT"
assert_not_empty "Cache is set after first check_yq call" "$cache_after_first"

# 2回目の呼び出し（キャッシュから返るはず）
check_yq || true
cache_after_second="$_YQ_CHECK_RESULT"
assert_equals "Cache remains same after second call" "$cache_after_first" "$cache_after_second"

# キャッシュ値の検証
if command -v yq &>/dev/null; then
    assert_equals "Cache value is '1' when yq exists" "1" "$_YQ_CHECK_RESULT"
else
    assert_equals "Cache value is '0' when yq not found" "0" "$_YQ_CHECK_RESULT"
fi

# ===================
# find_workflow_file テスト
# ===================
echo ""
echo "=== find_workflow_file tests ==="

setup_test_dir

# ビルトインへのフォールバック
result=$(find_workflow_file "default" "$TEST_DIR")
assert_equals "Returns builtin when no file exists" "builtin:default" "$result"

# workflows/default.yaml が存在する場合
cat > "$TEST_DIR/workflows/default.yaml" << 'EOF'
name: default
steps:
  - plan
  - implement
EOF

result=$(find_workflow_file "default" "$TEST_DIR")
assert_equals "Returns workflows/default.yaml when exists" "$TEST_DIR/workflows/default.yaml" "$result"

# .pi/workflow.yaml が優先される
cat > "$TEST_DIR/.pi/workflow.yaml" << 'EOF'
name: custom
steps:
  - implement
  - merge
EOF

result=$(find_workflow_file "default" "$TEST_DIR")
assert_equals ".pi/workflow.yaml takes priority" "$TEST_DIR/.pi/workflow.yaml" "$result"

cleanup_test_dir

# ===================
# find_agent_file テスト
# ===================
echo ""
echo "=== find_agent_file tests ==="

setup_test_dir

# ビルトインへのフォールバック
result=$(find_agent_file "plan" "$TEST_DIR")
assert_equals "Returns builtin when no agent file exists" "builtin:plan" "$result"

# agents/plan.md が存在する場合
echo "Custom plan agent" > "$TEST_DIR/agents/plan.md"
result=$(find_agent_file "plan" "$TEST_DIR")
assert_equals "Returns agents/plan.md when exists" "$TEST_DIR/agents/plan.md" "$result"

# .pi/agents/plan.md は agents/ より低優先度
mkdir -p "$TEST_DIR/.pi/agents"
echo "Pi plan agent" > "$TEST_DIR/.pi/agents/plan.md"
result=$(find_agent_file "plan" "$TEST_DIR")
assert_equals "agents/ takes priority over .pi/agents/" "$TEST_DIR/agents/plan.md" "$result"

# agents/がない場合は .pi/agents/ を使用
rm "$TEST_DIR/agents/plan.md"
result=$(find_agent_file "plan" "$TEST_DIR")
assert_equals "Falls back to .pi/agents/ when agents/ not found" "$TEST_DIR/.pi/agents/plan.md" "$result"

cleanup_test_dir

# ===================
# get_workflow_steps テスト
# ===================
echo ""
echo "=== get_workflow_steps tests ==="

# ビルトイン default
result=$(get_workflow_steps "builtin:default")
assert_equals "Builtin default workflow" "plan implement review merge" "$result"

# ビルトイン simple
result=$(get_workflow_steps "builtin:simple")
assert_equals "Builtin simple workflow" "implement merge" "$result"

# YAMLファイルからの読み込み（yqがある場合のみ）
if command -v yq &>/dev/null; then
    setup_test_dir
    
    cat > "$TEST_DIR/workflows/test.yaml" << 'EOF'
name: test
steps:
  - step1
  - step2
  - step3
EOF

    result=$(get_workflow_steps "$TEST_DIR/workflows/test.yaml")
    assert_equals "Steps from YAML file" "step1 step2 step3" "$result"
    
    cleanup_test_dir
else
    echo "(skipping YAML parsing test - yq not available)"
fi

# ===================
# render_template テスト
# ===================
echo ""
echo "=== render_template tests ==="

template="Issue #{{issue_number}} on branch {{branch_name}}"
result=$(render_template "$template" "42" "feature/test")
assert_equals "Basic template rendering" "Issue #42 on branch feature/test" "$result"

template="Step: {{step_name}}, Workflow: {{workflow_name}}"
result=$(render_template "$template" "" "" "" "implement" "default")
assert_equals "Step and workflow rendering" "Step: implement, Workflow: default" "$result"

template="Path: {{worktree_path}}"
result=$(render_template "$template" "" "" "/path/to/worktree")
assert_equals "Worktree path rendering" "Path: /path/to/worktree" "$result"

# 変数がない場合は空文字に置換
template="Issue #{{issue_number}}"
result=$(render_template "$template")
assert_equals "Empty variable becomes empty string" "Issue #" "$result"

# issue_title のテスト
template="Issue: {{issue_title}}"
result=$(render_template "$template" "" "" "" "" "default" "Fix bug in parser")
assert_equals "Issue title rendering" "Issue: Fix bug in parser" "$result"

# 複数変数の組み合わせテスト
template="Issue #{{issue_number}}: {{issue_title}} on {{branch_name}}"
result=$(render_template "$template" "42" "feature/test" "" "" "default" "Add new feature")
assert_equals "Combined issue_number, issue_title, branch_name" "Issue #42: Add new feature on feature/test" "$result"

# ===================
# get_agent_prompt テスト
# ===================
echo ""
echo "=== get_agent_prompt tests ==="

# ビルトインエージェント
result=$(get_agent_prompt "builtin:plan" "42")
assert_contains "Builtin plan agent contains issue number" "issue #42" "$result"

result=$(get_agent_prompt "builtin:implement" "99")
assert_contains "Builtin implement agent contains issue number" "issue #99" "$result"

# カスタムエージェントファイル
setup_test_dir
echo "Custom agent for issue #{{issue_number}}" > "$TEST_DIR/agents/custom.md"
result=$(get_agent_prompt "$TEST_DIR/agents/custom.md" "123")
assert_equals "Custom agent file with template" "Custom agent for issue #123" "$result"

# issue_title を含むカスタムエージェントファイル
echo "Issue #{{issue_number}}: {{issue_title}}" > "$TEST_DIR/agents/with_title.md"
result=$(get_agent_prompt "$TEST_DIR/agents/with_title.md" "42" "" "" "" "My Issue Title")
assert_equals "Custom agent with issue_title" "Issue #42: My Issue Title" "$result"
cleanup_test_dir

# ===================
# parse_step_result テスト
# ===================
echo ""
echo "=== parse_step_result tests ==="

result=$(parse_step_result "Task completed [DONE]")
assert_equals "Detects [DONE] marker" "DONE" "$result"

result=$(parse_step_result "Cannot proceed [BLOCKED] due to missing info")
assert_equals "Detects [BLOCKED] marker" "BLOCKED" "$result"

result=$(parse_step_result "Found issues [FIX_NEEDED]")
assert_equals "Detects [FIX_NEEDED] marker" "FIX_NEEDED" "$result"

result=$(parse_step_result "Some output without marker")
assert_equals "No marker defaults to DONE" "DONE" "$result"

# ===================
# run_step テスト
# ===================
echo ""
echo "=== run_step tests ==="

setup_test_dir

# ビルトインエージェントでの実行
result=$(run_step "plan" "42" "feature/test" "/path/worktree" "$TEST_DIR")
assert_contains "run_step returns prompt" "issue #42" "$result"

# カスタムエージェントでの実行
echo "Custom step for #{{issue_number}} on {{branch_name}}" > "$TEST_DIR/agents/custom.md"
result=$(run_step "custom" "55" "feature/custom" "/path" "$TEST_DIR")
assert_equals "run_step with custom agent" "Custom step for #55 on feature/custom" "$result"

cleanup_test_dir

# ===================
# run_workflow テスト
# ===================
echo ""
echo "=== run_workflow tests ==="

setup_test_dir

result=$(run_workflow "default" "42" "feature/test" "/path" "$TEST_DIR")
assert_contains "run_workflow outputs step:0" "step:0:plan" "$result"
assert_contains "run_workflow outputs step:1" "step:1:implement" "$result"
assert_contains "run_workflow outputs step:2" "step:2:review" "$result"
assert_contains "run_workflow outputs step:3" "step:3:merge" "$result"
assert_contains "run_workflow outputs total" "total:4" "$result"

result=$(run_workflow "simple" "42" "" "" "$TEST_DIR")
assert_contains "simple workflow step:0" "step:0:implement" "$result"
assert_contains "simple workflow step:1" "step:1:merge" "$result"
assert_contains "simple workflow total" "total:2" "$result"

cleanup_test_dir

# ===================
# get_workflow_steps_array テスト
# ===================
echo ""
echo "=== get_workflow_steps_array tests ==="

result=$(get_workflow_steps_array "default" "/nonexistent")
assert_equals "get_workflow_steps_array returns steps" "plan implement review merge" "$result"

# ===================
# 結果サマリー
# ===================
echo ""
echo "===================="
echo "Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "===================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
