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
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 5 && echo \$_PARSE_max_iterations"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]]
}

@test "parse_improve_arguments handles --max-issues" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-issues 10 && echo \$_PARSE_max_issues"
    [ "$status" -eq 0 ]
    [[ "$output" == *"10"* ]]
}

@test "parse_improve_arguments handles --timeout" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout 1800 && echo \$_PARSE_timeout"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1800"* ]]
}

@test "parse_improve_arguments handles --iteration" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --iteration 2 && echo \$_PARSE_iteration"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2"* ]]
}

@test "parse_improve_arguments handles --log-dir" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --log-dir /tmp/logs && echo \$_PARSE_log_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/logs"* ]]
}

@test "parse_improve_arguments handles --label" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --label test-session && echo \$_PARSE_session_label"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-session"* ]]
}

@test "parse_improve_arguments handles --dry-run" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --dry-run && echo \$_PARSE_dry_run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "parse_improve_arguments handles --review-only" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --review-only && echo \$_PARSE_review_only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "parse_improve_arguments handles --auto-continue" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --auto-continue && echo \$_PARSE_auto_continue"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
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
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && echo \$_PARSE_max_iterations"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
}

@test "parse_improve_arguments uses default max_issues" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && echo \$_PARSE_max_issues"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]]
}

@test "parse_improve_arguments uses default timeout" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && echo \$_PARSE_timeout"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3600"* ]]
}

@test "parse_improve_arguments uses default iteration" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && echo \$_PARSE_iteration"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
}

@test "parse_improve_arguments defaults log_dir to empty string" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && test -z \"\$_PARSE_log_dir\" && echo 'empty'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty"* ]]
}

@test "parse_improve_arguments defaults session_label to empty string" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && test -z \"\$_PARSE_session_label\" && echo 'empty'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty"* ]]
}

@test "parse_improve_arguments defaults boolean flags to false" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && echo \$_PARSE_dry_run \$_PARSE_review_only \$_PARSE_auto_continue"
    [ "$status" -eq 0 ]
    [[ "$output" == *"false false false"* ]]
}

# ====================
# parse_improve_arguments() - Edge Cases (no longer need escaping tests)
# ====================

@test "parse_improve_arguments handles single quotes in log_dir" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --log-dir \"/tmp/user's-logs\" && echo \$_PARSE_log_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/user's-logs"* ]]
}

@test "parse_improve_arguments handles single quotes in session_label" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --label \"test's-session\" && echo \$_PARSE_session_label"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test's-session"* ]]
}

@test "parse_improve_arguments handles multiple options combined" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 2 --max-issues 3 --timeout 600 && echo \$_PARSE_max_iterations \$_PARSE_max_issues \$_PARSE_timeout"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 3 600"* ]]
}

@test "parse_improve_arguments handles numeric zero values" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --max-iterations 0 && echo \$_PARSE_max_iterations"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]]
}

@test "parse_improve_arguments handles large numeric values" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --timeout 99999 && echo \$_PARSE_timeout"
    [ "$status" -eq 0 ]
    [[ "$output" == *"99999"* ]]
}

# ====================
# parse_improve_arguments() - Error Cases
# ====================

@test "parse_improve_arguments rejects unknown option" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments --unknown-option"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "parse_improve_arguments rejects unexpected positional argument" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments unexpected_arg"
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
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && echo \$_IMPROVE_DEFAULT_MAX_ITERATIONS"
    [ "$status" -eq 0 ]
    [[ "$output" == "3" ]]
}

@test "args.sh defines _IMPROVE_DEFAULT_MAX_ISSUES constant" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && echo \$_IMPROVE_DEFAULT_MAX_ISSUES"
    [ "$status" -eq 0 ]
    [[ "$output" == "5" ]]
}

@test "args.sh defines _IMPROVE_DEFAULT_TIMEOUT constant" {
    run bash -c "source '$PROJECT_ROOT/lib/improve/args.sh' && echo \$_IMPROVE_DEFAULT_TIMEOUT"
    [ "$status" -eq 0 ]
    [[ "$output" == "3600" ]]
}

@test "args.sh constants match default values in parse_improve_arguments" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh' && source '$PROJECT_ROOT/lib/improve/args.sh' && parse_improve_arguments && echo \$_PARSE_max_iterations"
    [ "$status" -eq 0 ]
    [[ "$output" == "3" ]]
}
