#!/usr/bin/env bats
# test/lib/improve/args.bats - Unit tests for lib/improve/args.sh

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
# Module Loading Tests
# ====================

@test "args.sh can be sourced" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "args.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/improve/args.sh"
    [ "$status" -eq 0 ]
}

@test "args.sh sets strict mode" {
    grep -q 'set -euo pipefail' "$PROJECT_ROOT/lib/improve/args.sh"
}

# ====================
# show_improve_usage() Tests
# ====================

@test "show_improve_usage displays usage header" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && show_improve_usage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: improve.sh"* ]]
}

@test "show_improve_usage displays all options" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && show_improve_usage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--max-iterations"* ]]
    [[ "$output" == *"--max-issues"* ]]
    [[ "$output" == *"--timeout"* ]]
    [[ "$output" == *"--iteration"* ]]
    [[ "$output" == *"--log-dir"* ]]
    [[ "$output" == *"--label"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--review-only"* ]]
    [[ "$output" == *"--auto-continue"* ]]
    [[ "$output" == *"--verbose"* ]]
}

@test "show_improve_usage displays description" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && show_improve_usage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Description:"* ]]
    [[ "$output" == *"2-phase approach"* ]]
}

@test "show_improve_usage displays examples" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && show_improve_usage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

@test "usage() is backward compatible wrapper" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && usage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: improve.sh"* ]]
}

# ====================
# parse_improve_arguments() - Normal Cases
# ====================

@test "parse_improve_arguments handles --max-iterations" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=5"* ]]
}

@test "parse_improve_arguments handles --max-issues" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-issues 10"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_issues=10"* ]]
}

@test "parse_improve_arguments handles --timeout" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout 1800"
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout=1800"* ]]
}

@test "parse_improve_arguments handles --iteration" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --iteration 2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"iteration=2"* ]]
}

@test "parse_improve_arguments handles --log-dir" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --log-dir /tmp/logs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"log_dir='/tmp/logs'"* ]]
}

@test "parse_improve_arguments handles --label" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --label test-session"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_label='test-session'"* ]]
}

@test "parse_improve_arguments handles --dry-run" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --dry-run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry_run=true"* ]]
}

@test "parse_improve_arguments handles --review-only" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --review-only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"review_only=true"* ]]
}

@test "parse_improve_arguments handles --auto-continue" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --auto-continue"
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto_continue=true"* ]]
}

@test "parse_improve_arguments handles --verbose" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --verbose && echo \"LOG_LEVEL=\$LOG_LEVEL\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG_LEVEL=DEBUG"* ]]
}

@test "parse_improve_arguments handles -v as verbose" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments -v && echo \"LOG_LEVEL=\$LOG_LEVEL\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG_LEVEL=DEBUG"* ]]
}

# ====================
# parse_improve_arguments() - Default Values
# ====================

@test "parse_improve_arguments uses default max_iterations" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=3"* ]]
}

@test "parse_improve_arguments uses default max_issues" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_issues=5"* ]]
}

@test "parse_improve_arguments uses default timeout" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout=3600"* ]]
}

@test "parse_improve_arguments uses default iteration" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"iteration=1"* ]]
}

@test "parse_improve_arguments defaults log_dir to empty string" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"log_dir=''"* ]]
}

@test "parse_improve_arguments defaults session_label to empty string" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_label=''"* ]]
}

@test "parse_improve_arguments defaults boolean flags to false" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry_run=false"* ]]
    [[ "$output" == *"review_only=false"* ]]
    [[ "$output" == *"auto_continue=false"* ]]
}

# ====================
# parse_improve_arguments() - Edge Cases
# ====================

@test "parse_improve_arguments escapes single quotes in log_dir" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --log-dir \"/tmp/user's-logs\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"log_dir='/tmp/user'\\''s-logs'"* ]]
}

@test "parse_improve_arguments escapes single quotes in session_label" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --label \"test's-session\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_label='test'\\''s-session'"* ]]
}

@test "parse_improve_arguments output is eval-able with single quotes" {
    run bash -c "
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/improve/args.sh'
        test_fn() {
            eval \"\$(parse_improve_arguments --log-dir \"/tmp/user's-logs\" --label \"test's-label\")\"
            echo \"log_dir=\$log_dir\"
            echo \"session_label=\$session_label\"
        }
        test_fn
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"log_dir=/tmp/user's-logs"* ]]
    [[ "$output" == *"session_label=test's-label"* ]]
}

@test "parse_improve_arguments handles multiple options combined" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 2 --max-issues 3 --timeout 1000 --dry-run --auto-continue"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=2"* ]]
    [[ "$output" == *"max_issues=3"* ]]
    [[ "$output" == *"timeout=1000"* ]]
    [[ "$output" == *"dry_run=true"* ]]
    [[ "$output" == *"auto_continue=true"* ]]
}

@test "parse_improve_arguments handles numeric zero values" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=0"* ]]
}

@test "parse_improve_arguments handles large numeric values" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout 99999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout=99999"* ]]
}

# ====================
# parse_improve_arguments() - Error Handling
# ====================

@test "parse_improve_arguments rejects unknown option" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --unknown-option 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "parse_improve_arguments rejects unexpected positional argument" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments unexpected_arg 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

@test "parse_improve_arguments shows usage on --help" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "parse_improve_arguments shows usage on -h" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments -h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ====================
# Constants Tests
# ====================

@test "args.sh defines _IMPROVE_DEFAULT_MAX_ITERATIONS constant" {
    grep -q '_IMPROVE_DEFAULT_MAX_ITERATIONS=' "$PROJECT_ROOT/lib/improve/args.sh"
}

@test "args.sh defines _IMPROVE_DEFAULT_MAX_ISSUES constant" {
    grep -q '_IMPROVE_DEFAULT_MAX_ISSUES=' "$PROJECT_ROOT/lib/improve/args.sh"
}

@test "args.sh defines _IMPROVE_DEFAULT_TIMEOUT constant" {
    grep -q '_IMPROVE_DEFAULT_TIMEOUT=' "$PROJECT_ROOT/lib/improve/args.sh"
}

@test "args.sh constants match default values in parse_improve_arguments" {
    # Extract constant values
    max_iter=$(grep '_IMPROVE_DEFAULT_MAX_ITERATIONS=' "$PROJECT_ROOT/lib/improve/args.sh" | sed 's/.*=\([0-9]*\).*/\1/')
    max_issues=$(grep '_IMPROVE_DEFAULT_MAX_ISSUES=' "$PROJECT_ROOT/lib/improve/args.sh" | sed 's/.*=\([0-9]*\).*/\1/')
    timeout=$(grep '_IMPROVE_DEFAULT_TIMEOUT=' "$PROJECT_ROOT/lib/improve/args.sh" | sed 's/.*=\([0-9]*\).*/\1/')
    
    # Test they match parsed defaults
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=$max_iter"* ]]
    [[ "$output" == *"max_issues=$max_issues"* ]]
    [[ "$output" == *"timeout=$timeout"* ]]
}
