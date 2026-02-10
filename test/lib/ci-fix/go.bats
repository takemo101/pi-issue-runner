#!/usr/bin/env bats
# test/lib/ci-fix/go.bats - go.sh のテスト

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
    unset _CI_FIX_GO_SH_SOURCED
    unset _LOG_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/go.sh"
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
# _fix_lint_go テスト
# ===================

@test "_fix_lint_go runs golangci-lint when available" {
    cat > "$MOCK_DIR/golangci-lint" << 'EOF'
#!/usr/bin/env bash
echo "golangci-lint $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/golangci-lint"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_lint_go
    [ "$status" -eq 0 ]
}

@test "_fix_lint_go returns 2 when golangci-lint not found" {
    if command -v golangci-lint &>/dev/null; then
        skip "golangci-lint is installed"
    fi
    run _fix_lint_go
    [ "$status" -eq 2 ]
}

@test "_fix_lint_go returns 1 when golangci-lint fails" {
    cat > "$MOCK_DIR/golangci-lint" << 'EOF'
#!/usr/bin/env bash
echo "error" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/golangci-lint"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_lint_go
    [ "$status" -eq 1 ]
}

# ===================
# _fix_format_go テスト
# ===================

@test "_fix_format_go runs gofmt when available" {
    cat > "$MOCK_DIR/gofmt" << 'EOF'
#!/usr/bin/env bash
echo "gofmt $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/gofmt"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_format_go
    [ "$status" -eq 0 ]
}

@test "_fix_format_go returns 1 when gofmt not found" {
    if command -v gofmt &>/dev/null; then
        skip "gofmt is installed"
    fi
    run _fix_format_go
    [ "$status" -eq 1 ]
}

@test "_fix_format_go returns 1 when gofmt fails" {
    cat > "$MOCK_DIR/gofmt" << 'EOF'
#!/usr/bin/env bash
echo "error" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/gofmt"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_format_go
    [ "$status" -eq 1 ]
}

# ===================
# _validate_go テスト
# ===================

@test "_validate_go returns 0 when go not found" {
    if command -v go &>/dev/null; then
        skip "go is installed"
    fi
    run _validate_go
    [ "$status" -eq 0 ]
}

@test "_validate_go runs go vet and go test" {
    cat > "$MOCK_DIR/go" << 'EOF'
#!/usr/bin/env bash
echo "go $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/go"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_go
    [ "$status" -eq 0 ]
}

@test "_validate_go fails when go vet fails" {
    cat > "$MOCK_DIR/go" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "vet" ]]; then
    echo "go vet error" >&2
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/go"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_go
    [ "$status" -eq 1 ]
}
