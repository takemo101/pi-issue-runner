#!/usr/bin/env bash
# workflow_test.sh - workflow.shの単体テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/workflow.sh"

# テスト結果カウンター
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# アサーション関数
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo "✓ PASS: $message"
    else
        ((TESTS_FAILED++))
        echo "✗ FAIL: $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
    fi
}

assert_contains() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    if [[ "$actual" == *"$expected"* ]]; then
        ((TESTS_PASSED++))
        echo "✓ PASS: $message"
    else
        ((TESTS_FAILED++))
        echo "✗ FAIL: $message"
        echo "  Expected to contain: $expected"
        echo "  Actual: $actual"
    fi
}

assert_not_empty() {
    local actual="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    if [[ -n "$actual" ]]; then
        ((TESTS_PASSED++))
        echo "✓ PASS: $message"
    else
        ((TESTS_FAILED++))
        echo "✗ FAIL: $message"
        echo "  Expected non-empty value, got empty"
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    if [[ -f "$file" ]]; then
        ((TESTS_PASSED++))
        echo "✓ PASS: $message"
    else
        ((TESTS_FAILED++))
        echo "✗ FAIL: $message"
        echo "  File not found: $file"
    fi
}

# テスト実行
echo "=== workflow.sh Tests ==="
echo ""

# Test: get_builtin_workflow_dir
echo "--- Testing get_builtin_workflow_dir ---"
builtin_dir="$(get_builtin_workflow_dir)"
assert_not_empty "$builtin_dir" "get_builtin_workflow_dir returns non-empty path"
assert_file_exists "$builtin_dir/default.yaml" "default.yaml exists in builtin dir"
assert_file_exists "$builtin_dir/simple.yaml" "simple.yaml exists in builtin dir"

# Test: get_builtin_agent_dir
echo ""
echo "--- Testing get_builtin_agent_dir ---"
agent_dir="$(get_builtin_agent_dir)"
assert_not_empty "$agent_dir" "get_builtin_agent_dir returns non-empty path"
assert_file_exists "$agent_dir/implement.md" "implement.md exists in agent dir"
assert_file_exists "$agent_dir/review.md" "review.md exists in agent dir"
assert_file_exists "$agent_dir/merge.md" "merge.md exists in agent dir"

# Test: find_workflow_file
echo ""
echo "--- Testing find_workflow_file ---"
default_workflow="$(find_workflow_file "default")"
assert_contains "default.yaml" "$default_workflow" "find_workflow_file finds default.yaml"

simple_workflow="$(find_workflow_file "simple")"
assert_contains "simple.yaml" "$simple_workflow" "find_workflow_file finds simple.yaml"

# Test: find_agent_file
echo ""
echo "--- Testing find_agent_file ---"
implement_agent="$(find_agent_file "implement")"
assert_contains "implement.md" "$implement_agent" "find_agent_file finds implement.md"

review_agent="$(find_agent_file "review")"
assert_contains "review.md" "$review_agent" "find_agent_file finds review.md"

# Test: render_template
echo ""
echo "--- Testing render_template ---"
template="Issue #{{issue_number}}: {{issue_title}} in {{branch_name}}"
rendered="$(render_template "$template" "42" "Test Issue" "feature/test" "/tmp/test")"
assert_equals "Issue #42: Test Issue in feature/test" "$rendered" "render_template replaces all variables"

# Test: get_workflow_steps
echo ""
echo "--- Testing get_workflow_steps ---"
default_steps="$(get_workflow_steps "$builtin_dir/default.yaml")"
assert_contains "plan" "$default_steps" "default workflow has plan step"
assert_contains "implement" "$default_steps" "default workflow has implement step"
assert_contains "review" "$default_steps" "default workflow has review step"
assert_contains "merge" "$default_steps" "default workflow has merge step"

simple_steps="$(get_workflow_steps "$builtin_dir/simple.yaml")"
assert_contains "implement" "$simple_steps" "simple workflow has implement step"
assert_contains "merge" "$simple_steps" "simple workflow has merge step"

# Test: get_workflow_name
echo ""
echo "--- Testing get_workflow_name ---"
workflow_name="$(get_workflow_name "$builtin_dir/default.yaml")"
assert_equals "default" "$workflow_name" "get_workflow_name returns correct name"

simple_name="$(get_workflow_name "$builtin_dir/simple.yaml")"
assert_equals "simple" "$simple_name" "get_workflow_name returns simple"

# Test: get_workflow_description
echo ""
echo "--- Testing get_workflow_description ---"
description="$(get_workflow_description "$builtin_dir/default.yaml")"
assert_not_empty "$description" "get_workflow_description returns non-empty"

# Test: list_available_workflows
echo ""
echo "--- Testing list_available_workflows ---"
workflows="$(list_available_workflows)"
assert_contains "default" "$workflows" "list_available_workflows includes default"
assert_contains "simple" "$workflows" "list_available_workflows includes simple"

# Test: generate_workflow_prompt
echo ""
echo "--- Testing generate_workflow_prompt ---"
prompt="$(generate_workflow_prompt "default" "99" "Test Issue Title" "Test issue body" "feature/test-99" "/tmp/worktree")"
assert_contains "Issue #99" "$prompt" "prompt contains issue number"
assert_contains "Test Issue Title" "$prompt" "prompt contains issue title"
assert_contains "Test issue body" "$prompt" "prompt contains issue body"
assert_contains "Workflow: default" "$prompt" "prompt contains workflow name"

# Test: write_workflow_prompt
echo ""
echo "--- Testing write_workflow_prompt ---"
temp_file="/tmp/test_workflow_prompt_$$.md"
write_workflow_prompt "$temp_file" "simple" "123" "Simple Test" "Simple body" "feature/simple-123" "/tmp/simple"
assert_file_exists "$temp_file" "write_workflow_prompt creates file"
file_content="$(cat "$temp_file")"
assert_contains "Issue #123" "$file_content" "written file contains issue number"
assert_contains "Workflow: simple" "$file_content" "written file contains workflow name"
rm -f "$temp_file"

# 結果サマリー
echo ""
echo "=== Test Summary ==="
echo "Total:  $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
