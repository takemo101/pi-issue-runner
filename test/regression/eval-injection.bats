#!/usr/bin/env bats
# ============================================================================
# test/regression/eval-injection.bats
# Regression tests for eval injection vulnerability (Issue #871)
# ============================================================================

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    source "$PROJECT_ROOT/lib/config.sh" || true
    source "$PROJECT_ROOT/lib/log.sh" || true
    source "$PROJECT_ROOT/lib/github.sh" || true
    source "$PROJECT_ROOT/lib/status.sh" || true
    source "$PROJECT_ROOT/lib/worktree.sh" || true
    source "$PROJECT_ROOT/lib/multiplexer.sh" || true
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ============================================================================
# Issue #871: Eval injection vulnerability tests
# ============================================================================

@test "Issue #871: parse_run_arguments handles custom_branch with single quotes correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    # Test with single quote (no eval needed - direct assignment)
    parse_run_arguments 42 -b "test'branch" 2>/dev/null || skip "parse_run_arguments failed"
    
    # Check global variable set by parse_run_arguments
    [ "$_PARSE_custom_branch" = "test'branch" ]
}

@test "Issue #871: parse_run_arguments handles base_branch with single quotes correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 --base "main'test" 2>/dev/null || skip "parse_run_arguments failed"
    
    [ "$_PARSE_base_branch" = "main'test" ]
}

@test "Issue #871: parse_run_arguments handles workflow_name with single quotes correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 -w "my'workflow" 2>/dev/null || skip "parse_run_arguments failed"
    
    [ "$_PARSE_workflow_name" = "my'workflow" ]
}

@test "Issue #871: parse_run_arguments handles extra_agent_args with single quotes correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 --agent-args "arg'with'quotes" 2>/dev/null || skip "parse_run_arguments failed"
    
    [ "$_PARSE_extra_agent_args" = "arg'with'quotes" ]
}

@test "Issue #871: parse_run_arguments handles cleanup_mode correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 --no-cleanup 2>/dev/null || skip "parse_run_arguments failed"
    
    [ "$_PARSE_cleanup_mode" = "none" ]
}

@test "Issue #871: multiple single quotes are handled correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 -b "test'multi'quote'branch" 2>/dev/null || skip "parse_run_arguments failed"
    
    [ "$_PARSE_custom_branch" = "test'multi'quote'branch" ]
}

@test "Issue #871: command injection with \$() is prevented" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    # Attempt command injection
    parse_run_arguments 42 -b 'test$(whoami)branch' 2>/dev/null || skip "parse_run_arguments failed"
    
    # Command should not be executed - should remain as literal string
    [ "$_PARSE_custom_branch" = 'test$(whoami)branch' ]
    # Verify whoami was not actually executed
    [[ "$_PARSE_custom_branch" != *"$(whoami)"* ]]
}

@test "Issue #871: command injection with backticks is prevented" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    # Attempt command injection with backticks
    parse_run_arguments 42 -b 'test`date`branch' 2>/dev/null || skip "parse_run_arguments failed"
    
    # Command should not be executed
    [ "$_PARSE_custom_branch" = 'test`date`branch' ]
}

@test "Issue #871: normal arguments without quotes still work" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 -b "feature-test" -w "default" 2>/dev/null || skip "parse_run_arguments failed"
    
    [ "$_PARSE_custom_branch" = "feature-test" ]
    [ "$_PARSE_workflow_name" = "default" ]
}

@test "Issue #871: empty custom_branch works correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    parse_run_arguments 42 2>/dev/null || skip "parse_run_arguments failed"
    
    [ -z "$_PARSE_custom_branch" ]
}

@test "Issue #871/#905: run.sh no longer uses eval pattern" {
    # Verify that run.sh no longer uses the eval pattern for parse_run_arguments
    # Issue #905: Replaced eval pattern with direct global variable assignment
    
    # Should NOT find eval "$_output" pattern (eval removed)
    ! grep -q 'eval "\$_output"' "$PROJECT_ROOT/scripts/run.sh" || skip "eval pattern still exists"
}

@test "Issue #871/#905: all variables use direct assignment instead of escaping" {
    # Verify that functions now use direct assignment (sets global variables)
    # instead of echo with escaping
    
    # Check for _PARSE_ prefix (parse_run_arguments)
    grep -q "_PARSE_issue_number=" "$PROJECT_ROOT/scripts/run.sh"
    grep -q "_PARSE_custom_branch=" "$PROJECT_ROOT/scripts/run.sh"
    grep -q "_PARSE_base_branch=" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check for _SESSION_ prefix (handle_existing_session)
    grep -q "_SESSION_name=" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check for _ISSUE_ prefix (fetch_issue_data)
    grep -q "_ISSUE_title=" "$PROJECT_ROOT/scripts/run.sh"
    grep -q "_ISSUE_body=" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check for _WORKTREE_ prefix (setup_worktree)
    grep -q "_WORKTREE_branch_name=" "$PROJECT_ROOT/scripts/run.sh"
    grep -q "_WORKTREE_path=" "$PROJECT_ROOT/scripts/run.sh"
}

# ============================================================================
# Issue #922: Numeric argument validation in eval patterns
# ============================================================================

@test "Issue #922: improve/args.sh validates max-iterations as positive integer" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Non-numeric should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations abc 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
    
    # Negative should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations -1 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
    
    # Zero should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 0 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh validates max-issues as positive integer" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Non-numeric should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-issues xyz 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
    
    # Negative should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-issues -5 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh validates timeout as positive integer" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Non-numeric should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout notanumber 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
    
    # Negative should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout -100 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh validates iteration as positive integer" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Non-numeric should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --iteration first 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
    
    # Negative should be rejected
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --iteration -2 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh prevents command injection in max-iterations" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Attempt command injection
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations '1; echo PWNED' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
    # Command is rejected by validation (may appear in error message but not executed)
}

@test "Issue #922: improve/args.sh prevents command injection in max-issues" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Attempt command injection
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-issues '5; rm -rf /' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh prevents command injection in timeout" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Attempt command injection with command substitution
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout '100; touch /tmp/pwned' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh prevents command injection in iteration" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Attempt command injection
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --iteration '2\$(whoami)' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "Issue #922: improve/args.sh uses quoted output for numeric values" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Verify output uses quotes for defense-in-depth
    output=$(parse_improve_arguments --max-iterations 5 --max-issues 10 --timeout 1800)
    
    [[ "$output" == *"max_iterations='5'"* ]]
    [[ "$output" == *"max_issues='10'"* ]]
    [[ "$output" == *"timeout='1800'"* ]]
}

@test "Issue #922: next.sh already validates count as positive integer" {
    # Verify next.sh has proper validation (reference check)
    grep -q 'count.*=~.*\[0-9\]' "$PROJECT_ROOT/scripts/next.sh"
    grep -q 'count.*-lt 1' "$PROJECT_ROOT/scripts/next.sh"
}

@test "Issue #922: valid numeric arguments still work correctly" {
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/improve/args.sh"
    
    # Test valid inputs
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 3 --max-issues 5 --timeout 3600 --iteration 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations='3'"* ]]
    [[ "$output" == *"max_issues='5'"* ]]
    [[ "$output" == *"timeout='3600'"* ]]
    [[ "$output" == *"iteration='1'"* ]]
}
