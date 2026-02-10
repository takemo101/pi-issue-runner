#!/usr/bin/env bats
# test/lib/ci-fix/common.bats - common.sh のテスト
# try_auto_fix(), try_fix_lint(), try_fix_format(), run_local_validation()

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"

    # ソースガードをリセット
    unset _CI_FIX_COMMON_SH_SOURCED
    unset _CI_FIX_DETECT_SH_SOURCED
    unset _CI_FIX_RUST_SH_SOURCED
    unset _CI_FIX_NODE_SH_SOURCED
    unset _CI_FIX_PYTHON_SH_SOURCED
    unset _CI_FIX_GO_SH_SOURCED
    unset _CI_FIX_BASH_SH_SOURCED
    unset _CI_CLASSIFIER_SH_SOURCED
    unset _LOG_SH_SOURCED
    unset _COMPAT_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/common.sh"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# try_auto_fix テスト
# ===================

@test "try_auto_fix returns 2 for test failure type" {
    run try_auto_fix "$FAILURE_TYPE_TEST" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix returns 2 for build failure type" {
    run try_auto_fix "$FAILURE_TYPE_BUILD" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix returns 2 for unknown failure type" {
    run try_auto_fix "$FAILURE_TYPE_UNKNOWN" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix routes lint type to try_fix_lint" {
    # unknown project → try_fix_lint returns 2
    local proj="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$proj"
    run try_auto_fix "$FAILURE_TYPE_LINT" "$proj"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix routes format type to try_fix_format" {
    # unknown project → try_fix_format returns 2
    local proj="$BATS_TEST_TMPDIR/empty2"
    mkdir -p "$proj"
    run try_auto_fix "$FAILURE_TYPE_FORMAT" "$proj"
    [ "$status" -eq 2 ]
}

# ===================
# try_fix_lint テスト
# ===================

@test "try_fix_lint returns 2 for unknown project type" {
    local proj="$BATS_TEST_TMPDIR/unknown-proj"
    mkdir -p "$proj"
    run try_fix_lint "$proj"
    [ "$status" -eq 2 ]
}

@test "try_fix_lint detects bash project and calls _fix_lint_bash" {
    # bash project → _fix_lint_bash returns 2 (shellcheck has no auto-fix)
    local proj="$BATS_TEST_TMPDIR/bash-proj"
    mkdir -p "$proj/test"
    touch "$proj/test/test_helper.bash"
    run try_fix_lint "$proj"
    [ "$status" -eq 2 ]
}

# ===================
# try_fix_format テスト
# ===================

@test "try_fix_format returns 2 for unknown project type" {
    local proj="$BATS_TEST_TMPDIR/unknown-proj2"
    mkdir -p "$proj"
    run try_fix_format "$proj"
    [ "$status" -eq 2 ]
}

# ===================
# run_local_validation テスト
# ===================

@test "run_local_validation returns 0 for unknown project type" {
    local proj="$BATS_TEST_TMPDIR/unknown-proj3"
    mkdir -p "$proj"
    run run_local_validation "$proj"
    [ "$status" -eq 0 ]
}

@test "run_local_validation defaults to current directory" {
    local proj="$BATS_TEST_TMPDIR/default-proj"
    mkdir -p "$proj"
    cd "$proj"
    run run_local_validation
    [ "$status" -eq 0 ]
}
