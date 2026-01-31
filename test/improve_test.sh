#!/usr/bin/env bash
# improve.sh tests - recursive approach

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPROVE_SCRIPT="$SCRIPT_DIR/../scripts/improve.sh"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

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

assert_not_contains() {
    local description="$1"
    local unexpected="$2"
    local actual="$3"
    if [[ "$actual" != *"$unexpected"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Should NOT contain: '$unexpected'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_success() {
    local description="$1"
    local exit_code="$2"
    if [[ "$exit_code" -eq 0 ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (exit code: $exit_code)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_failure() {
    local description="$1"
    local exit_code="$2"
    if [[ "$exit_code" -ne 0 ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (expected failure but got success)"
        ((TESTS_FAILED++)) || true
    fi
}

# ===================
# Help option tests
# ===================
echo "=== improve.sh help option tests ==="

# --help option
result=$("$IMPROVE_SCRIPT" --help 2>&1)
exit_code=$?
assert_success "--help returns success" "$exit_code"
assert_contains "--help shows usage" "Usage:" "$result"
assert_contains "--help shows --max-iterations option" "--max-iterations" "$result"
assert_contains "--help shows --max-issues option" "--max-issues" "$result"
assert_contains "--help shows --timeout option" "--timeout" "$result"
assert_contains "--help shows --iteration option" "--iteration" "$result"
assert_contains "--help shows -v/--verbose option" "--verbose" "$result"
assert_contains "--help shows -h/--help option" "--help" "$result"
assert_contains "--help shows description" "Description:" "$result"
assert_contains "--help shows examples" "Examples:" "$result"
assert_contains "--help shows environment variables" "Environment Variables:" "$result"

# -h option
result=$("$IMPROVE_SCRIPT" -h 2>&1)
exit_code=$?
assert_success "-h returns success" "$exit_code"
assert_contains "-h shows usage" "Usage:" "$result"

# ===================
# Option parsing tests
# ===================
echo ""
echo "=== improve.sh option parsing tests ==="

# Unknown option
result=$("$IMPROVE_SCRIPT" --unknown-option 2>&1)
exit_code=$?
assert_failure "improve.sh with unknown option fails" "$exit_code"
assert_contains "error message mentions unknown option" "Unknown option" "$result"

# Unexpected positional argument
result=$("$IMPROVE_SCRIPT" unexpected-arg 2>&1)
exit_code=$?
assert_failure "improve.sh with unexpected argument fails" "$exit_code"
assert_contains "error message mentions unexpected argument" "Unexpected argument" "$result"

# ===================
# Script structure tests
# ===================
echo ""
echo "=== Script structure tests ==="

# Syntax check
bash -n "$IMPROVE_SCRIPT" 2>&1
exit_code=$?
assert_success "improve.sh has valid bash syntax" "$exit_code"

# Source code verification
improve_source=$(cat "$IMPROVE_SCRIPT")

assert_contains "script sources config.sh" "lib/config.sh" "$improve_source"
assert_contains "script sources log.sh" "lib/log.sh" "$improve_source"
assert_contains "script has main function" "main()" "$improve_source"
assert_contains "script has usage function" "usage()" "$improve_source"
assert_contains "script has check_dependencies function" "check_dependencies()" "$improve_source"

# ===================
# New simplified design tests
# ===================
echo ""
echo "=== New simplified design tests ==="

# Role separation: pi as orchestrator
assert_contains "pi_command is used" 'pi_command=' "$improve_source"
assert_contains "pi is called with --message" '--message' "$improve_source"

# 3-phase structure
assert_contains "has PHASE 1" '[PHASE 1]' "$improve_source"
assert_contains "has PHASE 2" '[PHASE 2]' "$improve_source"
assert_contains "has PHASE 3" '[PHASE 3]' "$improve_source"

# Recursive call
assert_contains "uses exec for recursion" 'exec "$0"' "$improve_source"
assert_contains "passes iteration parameter" '--iteration' "$improve_source"

# Session monitoring
assert_contains "calls list.sh" 'list.sh' "$improve_source"
assert_contains "calls wait-for-sessions.sh" 'wait-for-sessions.sh' "$improve_source"

# ===================
# Completion marker detection tests
# ===================
echo ""
echo "=== Completion marker detection tests ==="

# Marker constants
assert_contains "defines MARKER_COMPLETE" 'MARKER_COMPLETE=' "$improve_source"
assert_contains "defines MARKER_NO_ISSUES" 'MARKER_NO_ISSUES=' "$improve_source"
assert_contains "MARKER_COMPLETE is ###TASK_COMPLETE###" '###TASK_COMPLETE###' "$improve_source"
assert_contains "MARKER_NO_ISSUES is ###NO_ISSUES###" '###NO_ISSUES###' "$improve_source"

# run_pi_with_completion_detection function
assert_contains "has run_pi_with_completion_detection function" 'run_pi_with_completion_detection()' "$improve_source"
assert_contains "function uses tee for output" 'tee' "$improve_source"
assert_contains "function monitors pi_pid" 'pi_pid' "$improve_source"
assert_contains "function creates temp file" 'mktemp' "$improve_source"
assert_contains "function checks MARKER_COMPLETE" 'grep -q "$MARKER_COMPLETE"' "$improve_source"
assert_contains "function checks MARKER_NO_ISSUES" 'grep -q "$MARKER_NO_ISSUES"' "$improve_source"
assert_contains "function cleans up temp file" 'rm -f "$output_file"' "$improve_source"

# Phase 1 uses the new function
assert_contains "Phase 1 uses run_pi_with_completion_detection" 'run_pi_with_completion_detection "$prompt" "$pi_command"' "$improve_source"

# Return value handling
assert_contains "handles no issues return" 'Improvement complete! No issues found.' "$improve_source"

# ===================
# Removed features tests
# ===================
echo ""
echo "=== Removed features tests ==="

# Removed options
assert_not_contains "no --dry-run option" '--dry-run)' "$improve_source"
assert_not_contains "no --review-only option" '--review-only)' "$improve_source"
assert_not_contains "no --auto-continue option" '--auto-continue)' "$improve_source"

# GitHub API related
assert_not_contains "no get_issues_created_after" 'get_issues_created_after' "$improve_source"
assert_not_contains "no CREATED_ISSUES array" 'CREATED_ISSUES=' "$improve_source"

# Removed sources
assert_not_contains "no status.sh source" 'source.*lib/status.sh' "$improve_source"
assert_not_contains "no github.sh source" 'source.*lib/github.sh' "$improve_source"

# ===================
# Option handling tests
# ===================
echo ""
echo "=== Option handling tests ==="

# --max-iterations
assert_contains "script handles --max-iterations" '--max-iterations)' "$improve_source"
assert_contains "script has max_iterations variable" 'max_iterations=' "$improve_source"

# --max-issues
assert_contains "script handles --max-issues" '--max-issues)' "$improve_source"
assert_contains "script has max_issues variable" 'max_issues=' "$improve_source"

# --timeout
assert_contains "script handles --timeout" '--timeout)' "$improve_source"
assert_contains "script has timeout variable" 'timeout=' "$improve_source"

# --iteration (internal use)
assert_contains "script handles --iteration" '--iteration)' "$improve_source"
assert_contains "script has iteration variable" 'iteration=' "$improve_source"

# -v/--verbose
assert_contains "script handles -v option" '-v|--verbose)' "$improve_source"
assert_contains "script sets LOG_LEVEL to DEBUG" 'LOG_LEVEL="DEBUG"' "$improve_source"

# ===================
# Default values tests
# ===================
echo ""
echo "=== Default values tests ==="

assert_contains "DEFAULT_MAX_ITERATIONS is 3" 'DEFAULT_MAX_ITERATIONS=3' "$improve_source"
assert_contains "DEFAULT_MAX_ISSUES is 5" 'DEFAULT_MAX_ISSUES=5' "$improve_source"
assert_contains "DEFAULT_TIMEOUT is 3600" 'DEFAULT_TIMEOUT=3600' "$improve_source"

# ===================
# Dependency check tests
# ===================
echo ""
echo "=== Dependency check tests ==="

# check_dependencies function content
assert_contains "checks for pi command" 'pi_command' "$improve_source"
assert_contains "checks for tmux command" 'command -v tmux' "$improve_source"
assert_contains "reports missing dependencies" 'Missing dependencies' "$improve_source"

# gh dependency is no longer required
assert_not_contains "does not check for gh" 'command -v gh' "$improve_source"

# ===================
# Iteration management tests
# ===================
echo ""
echo "=== Iteration management tests ==="

# Iteration limit check
assert_contains "checks iteration limit" 'iteration -gt $max_iterations' "$improve_source"
assert_contains "shows max iterations message" 'maximum iterations' "$improve_source"

# Iteration display
assert_contains "displays current iteration" 'Iteration $iteration/$max_iterations' "$improve_source"

# ===================
# Pi prompt tests
# ===================
echo ""
echo "=== Pi prompt tests ==="

# Prompt content verification
assert_contains "prompt uses project-review" 'project-review' "$improve_source"
assert_contains "prompt mentions Issue creation" 'GitHub Issue' "$improve_source"
assert_contains "prompt mentions run.sh" 'run.sh' "$improve_source"
assert_contains "prompt mentions --no-attach" '--no-attach' "$improve_source"
assert_contains "prompt mentions TASK_COMPLETE" 'TASK_COMPLETE' "$improve_source"

# ===================
# Completion tests
# ===================
echo ""
echo "=== Completion tests ==="

# No sessions means completion
assert_contains "shows no sessions message" 'No running sessions' "$improve_source"
assert_contains "shows completion message" 'Improvement complete' "$improve_source"

# ===================
# Result summary
# ===================
echo ""
echo "===================="
echo "Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "===================="

exit $TESTS_FAILED
