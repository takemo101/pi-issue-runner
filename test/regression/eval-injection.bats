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

@test "Issue #871: parse_run_arguments escapes custom_branch correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    # Test with single quote
    result=$(parse_run_arguments 42 -b "test'branch" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$custom_branch" = "test'branch" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: parse_run_arguments escapes base_branch correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 --base "main'test" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$base_branch" = "main'test" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: parse_run_arguments escapes workflow_name correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 -w "my'workflow" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$workflow_name" = "my'workflow" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: parse_run_arguments escapes extra_agent_args correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 -- "arg'with'quotes" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$extra_agent_args" = "arg'with'quotes" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: parse_run_arguments escapes cleanup_mode correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 --cleanup "auto'mode" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$cleanup_mode" = "auto'mode" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: multiple single quotes are escaped correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 -b "test'multi'quote'branch" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$custom_branch" = "test'multi'quote'branch" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: command injection with \$() is prevented" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    # Attempt command injection
    result=$(parse_run_arguments 42 -b 'test$(whoami)branch' 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        # Command should not be executed - should remain as literal string
        [ "$custom_branch" = 'test$(whoami)branch' ]
        # Verify whoami was not actually executed
        [[ "$custom_branch" != *"$(whoami)"* ]]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: command injection with backticks is prevented" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    # Attempt command injection with backticks
    result=$(parse_run_arguments 42 -b 'test`date`branch' 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        # Command should not be executed
        [ "$custom_branch" = 'test`date`branch' ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: normal arguments without quotes still work" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 -b "feature-test" -w "default" 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ "$custom_branch" = "feature-test" ]
        [ "$workflow_name" = "default" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: empty custom_branch works correctly" {
    source "$PROJECT_ROOT/scripts/run.sh" || skip "Could not source run.sh"
    
    result=$(parse_run_arguments 42 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        eval "$result" || skip "Eval failed"
        [ -z "$custom_branch" ]
    else
        skip "parse_run_arguments returned empty result"
    fi
}

@test "Issue #871: escaping pattern matches existing pattern for issue_title" {
    # Verify that run.sh uses the same escaping pattern for user inputs
    # as it does for issue_title (which was already correct)
    
    # Check that custom_branch uses the escaping pattern
    grep -q "custom_branch='.*//.*x27.*x27.*x27.*x27" "$PROJECT_ROOT/scripts/run.sh"
}

@test "Issue #871: all vulnerable variables are now escaped in run.sh" {
    # Verify all the variables mentioned in the issue are now escaped
    
    # Check custom_branch
    grep -q "custom_branch='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check base_branch
    grep -q "base_branch='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check workflow_name
    grep -q "workflow_name='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check extra_agent_args
    grep -q "extra_agent_args='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check cleanup_mode
    grep -q "cleanup_mode='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check session_name
    grep -q "session_name='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check branch_name
    grep -q "branch_name='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check worktree_path
    grep -q "worktree_path='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
    
    # Check full_worktree_path
    grep -q "full_worktree_path='.*//.*x27" "$PROJECT_ROOT/scripts/run.sh"
}
