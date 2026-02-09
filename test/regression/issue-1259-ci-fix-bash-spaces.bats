#!/usr/bin/env bats
# Regression test for Issue #1259
# https://github.com/kawasakiisao/pi-issue-runner/issues/1259
#
# ci-fix/bash.sh の find | xargs がスペースを含むファイルパスで破損する問題の回帰テスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    source "$PROJECT_ROOT/lib/ci-fix/bash.sh"

    # テスト用ディレクトリを作成（スペースを含む）
    export TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/project with spaces"
    mkdir -p "$TEST_PROJECT_DIR/dir with spaces"
    mkdir -p "$TEST_PROJECT_DIR/normal-dir"

    # テスト用 .sh ファイルを作成
    cat > "$TEST_PROJECT_DIR/dir with spaces/my script.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "hello"
SCRIPT

    cat > "$TEST_PROJECT_DIR/normal-dir/normal.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "world"
SCRIPT

    cat > "$TEST_PROJECT_DIR/top level script.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "top"
SCRIPT
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# Issue #1259: _fix_format_bash でスペースを含むパスの処理
# ====================

@test "Issue #1259: _fix_format_bash handles files with spaces in path" {
    # shfmt のモックを作成（引数にスペース付きファイルが正しく渡されることを確認）
    mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
    cat > "$BATS_TEST_TMPDIR/mock-bin/shfmt" << 'MOCK'
#!/usr/bin/env bash
# 各引数をファイルとして記録
for arg in "$@"; do
    if [[ "$arg" != "-w" ]]; then
        echo "$arg" >> "$BATS_TEST_TMPDIR/shfmt-args.txt"
    fi
done
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-bin/shfmt"
    export PATH="$BATS_TEST_TMPDIR/mock-bin:$PATH"

    cd "$TEST_PROJECT_DIR"
    run _fix_format_bash
    [ "$status" -eq 0 ]

    # shfmt に渡された引数を確認
    [ -f "$BATS_TEST_TMPDIR/shfmt-args.txt" ]

    # スペースを含むファイルが1つの引数として渡されていること
    run grep "dir with spaces/my script.sh" "$BATS_TEST_TMPDIR/shfmt-args.txt"
    [ "$status" -eq 0 ]

    run grep "top level script.sh" "$BATS_TEST_TMPDIR/shfmt-args.txt"
    [ "$status" -eq 0 ]

    run grep "normal-dir/normal.sh" "$BATS_TEST_TMPDIR/shfmt-args.txt"
    [ "$status" -eq 0 ]
}

# ====================
# Issue #1259: _validate_bash でスペースを含むパスの処理
# ====================

@test "Issue #1259: _validate_bash handles files with spaces in path" {
    # shellcheck のモックを作成
    mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
    cat > "$BATS_TEST_TMPDIR/mock-bin/shellcheck" << 'MOCK'
#!/usr/bin/env bash
# 各引数をファイルとして記録
for arg in "$@"; do
    if [[ "$arg" != "-x" ]]; then
        echo "$arg" >> "$BATS_TEST_TMPDIR/shellcheck-args.txt"
    fi
done
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock-bin/shellcheck"
    export PATH="$BATS_TEST_TMPDIR/mock-bin:$PATH"

    cd "$TEST_PROJECT_DIR"
    run _validate_bash
    [ "$status" -eq 0 ]

    # shellcheck に渡された引数を確認
    [ -f "$BATS_TEST_TMPDIR/shellcheck-args.txt" ]

    # スペースを含むファイルが1つの引数として渡されていること
    run grep "dir with spaces/my script.sh" "$BATS_TEST_TMPDIR/shellcheck-args.txt"
    [ "$status" -eq 0 ]

    run grep "top level script.sh" "$BATS_TEST_TMPDIR/shellcheck-args.txt"
    [ "$status" -eq 0 ]
}
