#!/usr/bin/env bats
# Regression test for Issue #1270
# grep fallback in _validate_node() should not match "test:unit" or "lint:fix"

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    export WORK_DIR="$BATS_TEST_TMPDIR/node-project"
    mkdir -p "$WORK_DIR"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "issue-1270: grep pattern does not match 'test:unit' as 'test'" {
    # "test:unit" should NOT match the pattern for "test"
    echo '"test:unit": "vitest"' > "$WORK_DIR/package.json"
    run grep -qE '"test"\s*:' "$WORK_DIR/package.json"
    [ "$status" -ne 0 ]
}

@test "issue-1270: grep pattern does not match 'lint:fix' as 'lint'" {
    # "lint:fix" should NOT match the pattern for "lint"
    echo '"lint:fix": "eslint --fix ."' > "$WORK_DIR/package.json"
    run grep -qE '"lint"\s*:' "$WORK_DIR/package.json"
    [ "$status" -ne 0 ]
}

@test "issue-1270: grep pattern matches exact 'test' key" {
    echo '"test": "vitest"' > "$WORK_DIR/package.json"
    run grep -qE '"test"\s*:' "$WORK_DIR/package.json"
    [ "$status" -eq 0 ]
}

@test "issue-1270: grep pattern matches exact 'lint' key" {
    echo '"lint": "eslint ."' > "$WORK_DIR/package.json"
    run grep -qE '"lint"\s*:' "$WORK_DIR/package.json"
    [ "$status" -eq 0 ]
}

@test "issue-1270: grep pattern matches 'test' with spaces before colon" {
    echo '"test" : "vitest"' > "$WORK_DIR/package.json"
    run grep -qE '"test"\s*:' "$WORK_DIR/package.json"
    [ "$status" -eq 0 ]
}
