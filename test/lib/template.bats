#!/usr/bin/env bats
# template.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    source "$PROJECT_ROOT/lib/template.sh"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ビルトインエージェント定数テスト
# ====================

@test "_BUILTIN_AGENT_PLAN is defined" {
    [ -n "$_BUILTIN_AGENT_PLAN" ]
}

@test "_BUILTIN_AGENT_IMPLEMENT is defined" {
    [ -n "$_BUILTIN_AGENT_IMPLEMENT" ]
}

@test "_BUILTIN_AGENT_REVIEW is defined" {
    [ -n "$_BUILTIN_AGENT_REVIEW" ]
}

@test "_BUILTIN_AGENT_MERGE is defined" {
    [ -n "$_BUILTIN_AGENT_MERGE" ]
}

@test "_BUILTIN_AGENT_PLAN contains issue_number placeholder" {
    [[ "$_BUILTIN_AGENT_PLAN" == *"{{issue_number}}"* ]]
}

@test "_BUILTIN_AGENT_IMPLEMENT contains issue_number placeholder" {
    [[ "$_BUILTIN_AGENT_IMPLEMENT" == *"{{issue_number}}"* ]]
}

@test "_BUILTIN_AGENT_REVIEW contains issue_number placeholder" {
    [[ "$_BUILTIN_AGENT_REVIEW" == *"{{issue_number}}"* ]]
}

@test "_BUILTIN_AGENT_MERGE contains issue_number placeholder" {
    [[ "$_BUILTIN_AGENT_MERGE" == *"{{issue_number}}"* ]]
}

# ====================
# render_template テスト
# ====================

@test "render_template renders issue_number and branch_name" {
    template="Issue #{{issue_number}} on branch {{branch_name}}"
    result="$(render_template "$template" "42" "feature/test")"
    [ "$result" = "Issue #42 on branch feature/test" ]
}

@test "render_template renders step_name and workflow_name" {
    template="Step: {{step_name}}, Workflow: {{workflow_name}}"
    result="$(render_template "$template" "" "" "" "implement" "default")"
    [ "$result" = "Step: implement, Workflow: default" ]
}

@test "render_template renders worktree_path" {
    template="Path: {{worktree_path}}"
    result="$(render_template "$template" "" "" "/path/to/worktree")"
    [ "$result" = "Path: /path/to/worktree" ]
}

@test "render_template replaces empty variable with empty string" {
    template="Issue #{{issue_number}}"
    result="$(render_template "$template")"
    [ "$result" = "Issue #" ]
}

@test "render_template renders issue_title" {
    template="Issue: {{issue_title}}"
    result="$(render_template "$template" "" "" "" "" "default" "Fix bug in parser")"
    [ "$result" = "Issue: Fix bug in parser" ]
}

@test "render_template combines issue_number, issue_title, branch_name" {
    template="Issue #{{issue_number}}: {{issue_title}} on {{branch_name}}"
    result="$(render_template "$template" "42" "feature/test" "" "" "default" "Add new feature")"
    [ "$result" = "Issue #42: Add new feature on feature/test" ]
}

@test "render_template handles multiple occurrences of same variable" {
    template="{{issue_number}} is #{{issue_number}}"
    result="$(render_template "$template" "42")"
    [ "$result" = "42 is #42" ]
}

@test "render_template handles all variables at once" {
    template="Issue #{{issue_number}}: {{issue_title}} on {{branch_name}} at {{worktree_path}}, step {{step_name}} of {{workflow_name}}"
    result="$(render_template "$template" "99" "fix/bug" "/tmp/wt" "implement" "default" "Fix Bug")"
    [ "$result" = "Issue #99: Fix Bug on fix/bug at /tmp/wt, step implement of default" ]
}

@test "render_template preserves text without variables" {
    template="No variables here"
    result="$(render_template "$template")"
    [ "$result" = "No variables here" ]
}

@test "render_template handles special characters in values" {
    template="Branch: {{branch_name}}"
    result="$(render_template "$template" "" "feature/add-special")"
    [ "$result" = "Branch: feature/add-special" ]
}

@test "render_template renders pr_number" {
    template="PR #{{pr_number}}"
    result="$(render_template "$template" "" "" "" "" "" "" "123")"
    [ "$result" = "PR #123" ]
}

@test "render_template handles pr_number with issue_number" {
    template="Issue #{{issue_number}}, PR #{{pr_number}}"
    result="$(render_template "$template" "42" "" "" "" "" "" "123")"
    [ "$result" = "Issue #42, PR #123" ]
}

@test "render_template renders all variables including pr_number" {
    template="Issue #{{issue_number}}: {{issue_title}} on {{branch_name}} at {{worktree_path}}, step {{step_name}} of {{workflow_name}}, PR #{{pr_number}}"
    result="$(render_template "$template" "99" "fix/bug" "/tmp/wt" "implement" "default" "Fix Bug" "555")"
    [ "$result" = "Issue #99: Fix Bug on fix/bug at /tmp/wt, step implement of default, PR #555" ]
}

@test "render_template renders plans_dir with default value" {
    template="Plan path: {{plans_dir}}/issue-{{issue_number}}-plan.md"
    result="$(render_template "$template" "42")"
    [ "$result" = "Plan path: docs/plans/issue-42-plan.md" ]
}

@test "render_template renders plans_dir with custom value" {
    template="Plan path: {{plans_dir}}/issue-{{issue_number}}-plan.md"
    result="$(render_template "$template" "42" "" "" "" "" "" "" "custom/plans")"
    [ "$result" = "Plan path: custom/plans/issue-42-plan.md" ]
}

@test "render_template renders all variables including plans_dir" {
    template="Issue #{{issue_number}}: {{issue_title}} on {{branch_name}} at {{worktree_path}}, step {{step_name}} of {{workflow_name}}, PR #{{pr_number}}, plans at {{plans_dir}}"
    result="$(render_template "$template" "99" "fix/bug" "/tmp/wt" "implement" "default" "Fix Bug" "555" "my/plans")"
    [ "$result" = "Issue #99: Fix Bug on fix/bug at /tmp/wt, step implement of default, PR #555, plans at my/plans" ]
}
