#!/usr/bin/env bats
# force-complete.sh のBatsテスト（廃止・リダイレクト確認）

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # テストではtmuxを使用
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    unset _CONFIG_LOADED
    unset _MUX_TYPE
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# 廃止テスト
# ====================

@test "force-complete.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -eq 0 ]
}

@test "force-complete.sh outputs deprecation warning" {
    # Without argument, it should fail but still show warning
    run "$PROJECT_ROOT/scripts/force-complete.sh" 2>&1 || true
    [[ "$output" == *"deprecated"* ]] || [[ "$output" == *"WARNING"* ]]
}

@test "force-complete.sh mentions stop.sh --cleanup in warning" {
    run "$PROJECT_ROOT/scripts/force-complete.sh" 2>&1 || true
    [[ "$output" == *"stop.sh"* ]] || [[ "$output" == *"--cleanup"* ]]
}

@test "force-complete.sh without argument fails" {
    run "$PROJECT_ROOT/scripts/force-complete.sh"
    [ "$status" -ne 0 ]
}

@test "force-complete.sh redirects to stop.sh" {
    grep -q 'exec.*stop.sh' "$PROJECT_ROOT/scripts/force-complete.sh"
}

@test "force-complete.sh passes --cleanup flag to stop.sh" {
    grep -q '\-\-cleanup' "$PROJECT_ROOT/scripts/force-complete.sh"
}
