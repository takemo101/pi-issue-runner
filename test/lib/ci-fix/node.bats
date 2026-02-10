#!/usr/bin/env bats
# test/lib/ci-fix/node.bats - node.sh のテスト

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
    unset _CI_FIX_NODE_SH_SOURCED
    unset _LOG_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/node.sh"
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
# _fix_lint_node テスト
# ===================

@test "_fix_lint_node runs npm run lint:fix when available" {
    local proj="$BATS_TEST_TMPDIR/node-lint-proj"
    mkdir -p "$proj"
    echo '{"scripts":{"lint:fix":"echo fixed"}}' > "$proj/package.json"

    cat > "$MOCK_DIR/npm" << 'EOF'
#!/usr/bin/env bash
echo "npm $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/npm"
    export PATH="$MOCK_DIR:$PATH"

    cd "$proj"
    run _fix_lint_node
    [ "$status" -eq 0 ]
}

@test "_fix_lint_node falls back to npx eslint --fix" {
    local proj="$BATS_TEST_TMPDIR/node-eslint-proj"
    mkdir -p "$proj"
    echo '{"scripts":{}}' > "$proj/package.json"

    cat > "$MOCK_DIR/npx" << 'EOF'
#!/usr/bin/env bash
echo "npx $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/npx"
    export PATH="$MOCK_DIR:$PATH"

    cd "$proj"
    run _fix_lint_node
    [ "$status" -eq 0 ]
}

@test "_fix_lint_node returns 2 when no tools available" {
    local proj="$BATS_TEST_TMPDIR/node-no-tools"
    mkdir -p "$proj"
    echo '{"scripts":{}}' > "$proj/package.json"

    # npxもnpmもない環境を模倣
    local empty_dir="$BATS_TEST_TMPDIR/empty-bin"
    mkdir -p "$empty_dir"

    # npxが存在しない場合をテスト - command -v npxが失敗する必要がある
    # 実際の環境では npx がインストール済みの可能性が高いのでスキップ
    if command -v npx &>/dev/null; then
        skip "npx is installed, cannot test 'no tools' path"
    fi

    cd "$proj"
    run _fix_lint_node
    [ "$status" -eq 2 ]
}

# ===================
# _fix_format_node テスト
# ===================

@test "_fix_format_node runs npm run format when available" {
    local proj="$BATS_TEST_TMPDIR/node-fmt-proj"
    mkdir -p "$proj"
    echo '{"scripts":{"format":"echo formatted"}}' > "$proj/package.json"

    cat > "$MOCK_DIR/npm" << 'EOF'
#!/usr/bin/env bash
echo "npm $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/npm"
    export PATH="$MOCK_DIR:$PATH"

    cd "$proj"
    run _fix_format_node
    [ "$status" -eq 0 ]
}

@test "_fix_format_node falls back to npx prettier --write" {
    local proj="$BATS_TEST_TMPDIR/node-prettier-proj"
    mkdir -p "$proj"
    echo '{"scripts":{}}' > "$proj/package.json"

    cat > "$MOCK_DIR/npx" << 'EOF'
#!/usr/bin/env bash
echo "npx $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/npx"
    export PATH="$MOCK_DIR:$PATH"

    cd "$proj"
    run _fix_format_node
    [ "$status" -eq 0 ]
}

# ===================
# _validate_node テスト
# ===================

@test "_validate_node returns 0 when no scripts defined" {
    local proj="$BATS_TEST_TMPDIR/node-empty-proj"
    mkdir -p "$proj"
    echo '{"name":"test"}' > "$proj/package.json"

    cd "$proj"
    run _validate_node
    [ "$status" -eq 0 ]
}

@test "_validate_node runs lint and test scripts when defined" {
    local proj="$BATS_TEST_TMPDIR/node-full-proj"
    mkdir -p "$proj"
    echo '{"scripts":{"lint":"echo lint ok","test":"echo test ok"}}' > "$proj/package.json"

    cat > "$MOCK_DIR/npm" << 'EOF'
#!/usr/bin/env bash
echo "npm $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/npm"
    export PATH="$MOCK_DIR:$PATH"

    cd "$proj"
    run _validate_node
    [ "$status" -eq 0 ]
}

@test "_validate_node fails when lint fails" {
    local proj="$BATS_TEST_TMPDIR/node-lint-fail"
    mkdir -p "$proj"
    echo '{"scripts":{"lint":"exit 1"}}' > "$proj/package.json"

    cat > "$MOCK_DIR/npm" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "lint" ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/npm"
    export PATH="$MOCK_DIR:$PATH"

    cd "$proj"
    run _validate_node
    [ "$status" -eq 1 ]
}
