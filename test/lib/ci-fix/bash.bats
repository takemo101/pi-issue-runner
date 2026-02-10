#!/usr/bin/env bats
# test/lib/ci-fix/bash.bats - bash.sh のテスト

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
    unset _CI_FIX_BASH_SH_SOURCED
    unset _LOG_SH_SOURCED
    unset _COMPAT_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/bash.sh"
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
# _fix_lint_bash テスト
# ===================

@test "_fix_lint_bash returns 2 (auto-fix not supported)" {
    run _fix_lint_bash
    [ "$status" -eq 2 ]
}

# ===================
# _fix_format_bash テスト
# ===================

@test "_fix_format_bash returns 2 when shfmt not found" {
    # shfmtをPATHから除外
    cat > "$MOCK_DIR/shfmt" << 'EOF'
#!/usr/bin/env bash
exit 127
EOF
    # shfmtを隠す（PATHにモックなしの状態）
    export PATH="$MOCK_DIR/empty:$ORIGINAL_PATH"
    mkdir -p "$MOCK_DIR/empty"

    # shfmtがない場合のテスト - 環境依存を避けるため直接確認
    if ! command -v shfmt &>/dev/null; then
        run _fix_format_bash
        [ "$status" -eq 2 ]
    else
        skip "shfmt is installed, cannot test 'not found' path"
    fi
}

@test "_fix_format_bash returns 2 when no .sh files found" {
    # shfmtモックを作成
    cat > "$MOCK_DIR/shfmt" << 'EOF'
#!/usr/bin/env bash
echo "shfmt called"
exit 0
EOF
    chmod +x "$MOCK_DIR/shfmt"
    export PATH="$MOCK_DIR:$PATH"

    # 空ディレクトリに移動
    local proj="$BATS_TEST_TMPDIR/empty-proj"
    mkdir -p "$proj"
    cd "$proj"

    run _fix_format_bash
    [ "$status" -eq 2 ]
}

@test "_fix_format_bash runs shfmt on .sh files" {
    cat > "$MOCK_DIR/shfmt" << 'EOF'
#!/usr/bin/env bash
echo "shfmt -w $@"
exit 0
EOF
    chmod +x "$MOCK_DIR/shfmt"
    export PATH="$MOCK_DIR:$PATH"

    local proj="$BATS_TEST_TMPDIR/sh-proj"
    mkdir -p "$proj"
    echo "#!/bin/bash" > "$proj/test.sh"
    cd "$proj"

    run _fix_format_bash
    [ "$status" -eq 0 ]
}

# ===================
# _validate_bash テスト
# ===================

@test "_validate_bash returns 0 when no tools installed" {
    # Empty dir: no .sh files (shellcheck skip), no test dir (bats skip)
    local proj="$BATS_TEST_TMPDIR/no-tools-proj"
    mkdir -p "$proj"
    cd "$proj"

    run _validate_bash
    [ "$status" -eq 0 ]
}

@test "_validate_bash runs shellcheck on .sh files" {
    local proj="$BATS_TEST_TMPDIR/sc-proj"
    mkdir -p "$proj"
    # 有効なシェルスクリプトを作成
    cat > "$proj/valid.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
SCRIPT
    cd "$proj"

    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi

    run _validate_bash
    [ "$status" -eq 0 ]
}

@test "_validate_bash fails on shellcheck errors" {
    local proj="$BATS_TEST_TMPDIR/sc-fail-proj"
    mkdir -p "$proj"
    # ShellCheck が警告を出すスクリプト
    cat > "$proj/bad.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo $UNDEFINED_VAR
SCRIPT
    cd "$proj"

    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi

    run _validate_bash
    [ "$status" -eq 1 ]
}
