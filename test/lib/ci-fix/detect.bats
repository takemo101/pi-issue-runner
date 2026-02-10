#!/usr/bin/env bats
# test/lib/ci-fix/detect.bats - detect_project_type() のテスト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    # ソースガードをリセット
    unset _CI_FIX_DETECT_SH_SOURCED
    source "$PROJECT_ROOT/lib/ci-fix/detect.sh"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# Rust検出
# ===================

@test "detect_project_type detects rust project" {
    local proj="$BATS_TEST_TMPDIR/rust-proj"
    mkdir -p "$proj"
    touch "$proj/Cargo.toml"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

# ===================
# Node検出
# ===================

@test "detect_project_type detects node project" {
    local proj="$BATS_TEST_TMPDIR/node-proj"
    mkdir -p "$proj"
    echo '{"name":"test"}' > "$proj/package.json"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "node" ]
}

# ===================
# Python検出
# ===================

@test "detect_project_type detects python project with pyproject.toml" {
    local proj="$BATS_TEST_TMPDIR/py-proj"
    mkdir -p "$proj"
    touch "$proj/pyproject.toml"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type detects python project with setup.py" {
    local proj="$BATS_TEST_TMPDIR/py-proj2"
    mkdir -p "$proj"
    touch "$proj/setup.py"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

# ===================
# Go検出
# ===================

@test "detect_project_type detects go project" {
    local proj="$BATS_TEST_TMPDIR/go-proj"
    mkdir -p "$proj"
    touch "$proj/go.mod"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

# ===================
# Bash検出
# ===================

@test "detect_project_type detects bash project with .bats files" {
    local proj="$BATS_TEST_TMPDIR/bash-proj"
    mkdir -p "$proj"
    touch "$proj/example.bats"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "detect_project_type detects bash project with test_helper.bash" {
    local proj="$BATS_TEST_TMPDIR/bash-proj2"
    mkdir -p "$proj/test"
    touch "$proj/test/test_helper.bash"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

# ===================
# Unknown検出
# ===================

@test "detect_project_type returns unknown for empty directory" {
    local proj="$BATS_TEST_TMPDIR/empty-proj"
    mkdir -p "$proj"
    run detect_project_type "$proj"
    [ "$status" -eq 1 ]
    [ "$output" = "unknown" ]
}

# ===================
# 優先順位テスト
# ===================

@test "detect_project_type prioritizes rust over node" {
    local proj="$BATS_TEST_TMPDIR/mixed-proj"
    mkdir -p "$proj"
    touch "$proj/Cargo.toml"
    echo '{"name":"test"}' > "$proj/package.json"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

@test "detect_project_type prioritizes node over python" {
    local proj="$BATS_TEST_TMPDIR/mixed-proj2"
    mkdir -p "$proj"
    echo '{"name":"test"}' > "$proj/package.json"
    touch "$proj/pyproject.toml"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "node" ]
}

@test "detect_project_type prioritizes python over go" {
    local proj="$BATS_TEST_TMPDIR/mixed-proj3"
    mkdir -p "$proj"
    touch "$proj/pyproject.toml"
    touch "$proj/go.mod"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type prioritizes go over bash" {
    local proj="$BATS_TEST_TMPDIR/mixed-proj4"
    mkdir -p "$proj"
    touch "$proj/go.mod"
    touch "$proj/example.bats"
    run detect_project_type "$proj"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

# ===================
# デフォルトパス
# ===================

@test "detect_project_type defaults to current directory" {
    local proj="$BATS_TEST_TMPDIR/default-proj"
    mkdir -p "$proj"
    touch "$proj/Cargo.toml"
    cd "$proj"
    run detect_project_type
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}
