#!/usr/bin/env bats
# test/scripts/sweep.bats - Tests for sweep.sh

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_BIN="${BATS_TEST_TMPDIR}/mock_bin"
    mkdir -p "$MOCK_BIN"
    export ORIGINAL_PATH="$PATH"
    export PATH="$MOCK_BIN:$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "sweep.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/sweep.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "sweep.sh fails with invalid option" {
    run "$PROJECT_ROOT/scripts/sweep.sh" --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "sweep.sh runs with --dry-run when no sessions (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh detects session with COMPLETE marker (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh ignores COMPLETE marker in code block (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh detects ERROR marker with --check-errors (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh does not detect ERROR marker without --check-errors (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh shows summary (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}

@test "sweep.sh executes cleanup (manual test)" {
    skip "Requires actual multiplexer setup - tested manually"
}
