#!/usr/bin/env bats
# test/lib/ci-fix/python.bats - python.sh のテスト

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
    unset _CI_FIX_PYTHON_SH_SOURCED
    unset _LOG_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/python.sh"
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
# _fix_lint_python テスト
# ===================

@test "_fix_lint_python runs autopep8 when available" {
    cat > "$MOCK_DIR/autopep8" << 'EOF'
#!/usr/bin/env bash
echo "autopep8 $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/autopep8"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_lint_python
    [ "$status" -eq 0 ]
}

@test "_fix_lint_python returns 2 when autopep8 not found" {
    if command -v autopep8 &>/dev/null; then
        skip "autopep8 is installed"
    fi
    run _fix_lint_python
    [ "$status" -eq 2 ]
}

# ===================
# _fix_format_python テスト
# ===================

@test "_fix_format_python prefers black over autopep8" {
    cat > "$MOCK_DIR/black" << 'EOF'
#!/usr/bin/env bash
echo "black $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/black"
    cat > "$MOCK_DIR/autopep8" << 'EOF'
#!/usr/bin/env bash
echo "autopep8 $@" >> "$MOCK_DIR/autopep8.log"
exit 0
EOF
    chmod +x "$MOCK_DIR/autopep8"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_format_python
    [ "$status" -eq 0 ]
    [[ "$output" == *"black"* ]]
}

@test "_fix_format_python falls back to autopep8" {
    # blackがない場合
    if command -v black &>/dev/null; then
        skip "black is installed"
    fi

    cat > "$MOCK_DIR/autopep8" << 'EOF'
#!/usr/bin/env bash
echo "autopep8 $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/autopep8"
    export PATH="$MOCK_DIR:$PATH"

    run _fix_format_python
    [ "$status" -eq 0 ]
}

@test "_fix_format_python returns 2 when no formatter found" {
    if command -v black &>/dev/null || command -v autopep8 &>/dev/null; then
        skip "Python formatter is installed"
    fi
    run _fix_format_python
    [ "$status" -eq 2 ]
}

# ===================
# _validate_python テスト
# ===================

@test "_validate_python returns 0 when no tools installed" {
    if command -v flake8 &>/dev/null || command -v pytest &>/dev/null; then
        skip "Python tools are installed"
    fi
    run _validate_python
    [ "$status" -eq 0 ]
}

@test "_validate_python runs flake8 when available" {
    cat > "$MOCK_DIR/flake8" << 'EOF'
#!/usr/bin/env bash
echo "flake8 ok"
exit 0
EOF
    chmod +x "$MOCK_DIR/flake8"
    # pytest もモックして副作用を防ぐ
    cat > "$MOCK_DIR/pytest" << 'EOF'
#!/usr/bin/env bash
echo "pytest ok"
exit 0
EOF
    chmod +x "$MOCK_DIR/pytest"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_python
    [ "$status" -eq 0 ]
}

@test "_validate_python fails when flake8 fails" {
    cat > "$MOCK_DIR/flake8" << 'EOF'
#!/usr/bin/env bash
echo "flake8 error" >&2
exit 1
EOF
    chmod +x "$MOCK_DIR/flake8"
    export PATH="$MOCK_DIR:$PATH"

    run _validate_python
    [ "$status" -eq 1 ]
}
