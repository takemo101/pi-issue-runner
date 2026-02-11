#!/usr/bin/env bats
# lib/run/args.sh のBatsテスト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# parse_run_arguments テスト
# ====================

@test "args.sh: parse_run_arguments sets _PARSE_issue_number from positional arg" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    # Mock resolve_default_workflow
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_issue_number" = "42" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_issue_number from --issue" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments --issue 42
    [ "$_PARSE_issue_number" = "42" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_issue_number from -i" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments -i 42
    [ "$_PARSE_issue_number" = "42" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_custom_branch from --branch" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --branch my-feature
    [ "$_PARSE_custom_branch" = "my-feature" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_custom_branch from -b" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 -b my-feature
    [ "$_PARSE_custom_branch" = "my-feature" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_base_branch from --base" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --base develop
    [ "$_PARSE_base_branch" = "develop" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_workflow_name from --workflow" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    parse_run_arguments 42 --workflow simple
    [ "$_PARSE_workflow_name" = "simple" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_workflow_name from -w" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    parse_run_arguments 42 -w thorough
    [ "$_PARSE_workflow_name" = "thorough" ]
}

@test "args.sh: parse_run_arguments calls resolve_default_workflow when -w not specified" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    # Create a temp file to track if resolve_default_workflow was called
    local tracking_file="$BATS_TEST_TMPDIR/resolved"
    touch "$tracking_file"
    
    resolve_default_workflow() { 
        echo "true" > "$tracking_file"
        echo "default"
    }
    
    parse_run_arguments 42
    [ "$(cat "$tracking_file")" = "true" ]
    [ "$_PARSE_workflow_name" = "default" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_no_attach from --no-attach" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --no-attach
    [ "$_PARSE_no_attach" = "true" ]
}

@test "args.sh: _PARSE_no_attach defaults to false" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_no_attach" = "false" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_reattach from --reattach" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --reattach
    [ "$_PARSE_reattach" = "true" ]
}

@test "args.sh: _PARSE_reattach defaults to false" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_reattach" = "false" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_force from --force" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --force
    [ "$_PARSE_force" = "true" ]
}

@test "args.sh: _PARSE_force defaults to false" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_force" = "false" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_cleanup_mode to none from --no-cleanup" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --no-cleanup
    [ "$_PARSE_cleanup_mode" = "none" ]
}

@test "args.sh: _PARSE_cleanup_mode defaults to auto" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_cleanup_mode" = "auto" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_ignore_blockers from --ignore-blockers" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --ignore-blockers
    [ "$_PARSE_ignore_blockers" = "true" ]
}

@test "args.sh: _PARSE_ignore_blockers defaults to false" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_ignore_blockers" = "false" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_session_label from --label" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --label my-label
    [ "$_PARSE_session_label" = "my-label" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_session_label from -l" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 -l my-label
    [ "$_PARSE_session_label" = "my-label" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_extra_agent_args from --agent-args" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --agent-args "--model opus"
    [ "$_PARSE_extra_agent_args" = "--model opus" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_extra_agent_args from --pi-args" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --pi-args "--some-arg"
    [ "$_PARSE_extra_agent_args" = "--some-arg" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_no_gates from --no-gates" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --no-gates
    [ "$_PARSE_no_gates" = "true" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_no_gates from --skip-run" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --skip-run
    [ "$_PARSE_no_gates" = "true" ]
}

@test "args.sh: _PARSE_no_gates defaults to false" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_no_gates" = "false" ]
}

@test "args.sh: parse_run_arguments sets _PARSE_skip_call from --skip-call" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --skip-call
    [ "$_PARSE_skip_call" = "true" ]
}

@test "args.sh: _PARSE_skip_call defaults to false" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42
    [ "$_PARSE_skip_call" = "false" ]
}

@test "args.sh: parse_run_arguments handles multiple options together" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    resolve_default_workflow() { echo "default"; }
    
    parse_run_arguments 42 --branch my-branch --workflow simple --no-attach --force
    [ "$_PARSE_issue_number" = "42" ]
    [ "$_PARSE_custom_branch" = "my-branch" ]
    [ "$_PARSE_workflow_name" = "simple" ]
    [ "$_PARSE_no_attach" = "true" ]
    [ "$_PARSE_force" = "true" ]
}

# ====================
# validate_run_inputs テスト
# ====================

@test "args.sh: validate_run_inputs exits with 0 for valid issue number" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    # Mock list_available_workflows and load_config
    list_available_workflows() { :; }
    load_config() { :; }
    
    run validate_run_inputs "42" "false"
    [ "$status" -eq 0 ]
}

@test "args.sh: validate_run_inputs exits with 1 for empty issue number" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    list_available_workflows() { :; }
    load_config() { :; }
    
    run validate_run_inputs "" "false"
    [ "$status" -eq 1 ]
}

@test "args.sh: validate_run_inputs exits with 1 for non-numeric issue number" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    list_available_workflows() { :; }
    load_config() { :; }
    
    run validate_run_inputs "abc" "false"
    [ "$status" -eq 1 ]
}

@test "args.sh: validate_run_inputs exits with 0 when list_workflows is true" {
    source "$PROJECT_ROOT/lib/run/args.sh" 2>/dev/null || true
    
    list_available_workflows() { echo "workflows listed"; }
    load_config() { :; }
    
    run validate_run_inputs "" "true"
    [ "$status" -eq 0 ]
}

# ====================
# ソースガードテスト
# ====================

@test "args.sh: source guard prevents multiple sourcing" {
    # First source
    source "$PROJECT_ROOT/lib/run/args.sh"
    
    # Second source should return early
    source "$PROJECT_ROOT/lib/run/args.sh"
    
    # If we get here without errors, the source guard worked
    [ -n "${_RUN_ARGS_SH_SOURCED:-}" ]
}
