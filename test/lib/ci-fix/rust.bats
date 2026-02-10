#!/usr/bin/env bats
# test/lib/ci-fix/rust.bats - rust.sh のテスト

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
    unset _CI_FIX_RUST_SH_SOURCED
    unset _LOG_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/rust.sh"
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
# _fix_lint_rust テスト
# ===================

@test "_fix_lint_rust runs cargo clippy --fix when available" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
echo "cargo $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_lint_rust
    [ "$status" -eq 0 ]
}

@test "_fix_lint_rust returns 1 when cargo not found" {
    if command -v cargo &>/dev/null; then
        skip "cargo is installed"
    fi
    run _fix_lint_rust
    [ "$status" -eq 1 ]
}

@test "_fix_lint_rust returns 1 when clippy fails" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
echo "clippy error" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_lint_rust
    [ "$status" -eq 1 ]
}

# ===================
# _fix_format_rust テスト
# ===================

@test "_fix_format_rust runs cargo fmt when available" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
echo "cargo $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_format_rust
    [ "$status" -eq 0 ]
}

@test "_fix_format_rust returns 1 when cargo not found" {
    if command -v cargo &>/dev/null; then
        skip "cargo is installed"
    fi
    run _fix_format_rust
    [ "$status" -eq 1 ]
}

@test "_fix_format_rust returns 1 when fmt fails" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
echo "fmt error" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_format_rust
    [ "$status" -eq 1 ]
}

# ===================
# _validate_rust テスト
# ===================

@test "_validate_rust returns 0 when cargo not found" {
    if command -v cargo &>/dev/null; then
        skip "cargo is installed"
    fi
    run _validate_rust
    [ "$status" -eq 0 ]
}

@test "_validate_rust runs clippy and test" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
echo "cargo $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_rust
    [ "$status" -eq 0 ]
}

@test "_validate_rust fails when clippy fails" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "clippy" ]]; then
    echo "clippy error" >&2
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_rust
    [ "$status" -eq 1 ]
}

@test "_validate_rust fails when test fails" {
    cat > "$MOCK_DIR/cargo" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "test" ]]; then
    echo "test error" >&2
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/cargo"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_rust
    [ "$status" -eq 1 ]
}
