#!/usr/bin/env bats
# test/regression/escalation-literal-newline.bats
# Issue #1233: escalate_to_manual() がリテラル \n を出力していた問題の回帰テスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi

    # gh モックを作成
    local mock_stdin="$BATS_TEST_TMPDIR/gh_stdin.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << MOCK_EOF
#!/usr/bin/env bash
case "\$*" in
    "pr ready"*"--undo"*)
        exit 0
        ;;
    "pr comment"*)
        cat > "$mock_stdin"
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    source "$PROJECT_ROOT/lib/ci-fix/escalation.sh"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "escalate_to_manual comment does not contain literal backslash-n" {
    run escalate_to_manual 99 "some failure log"
    [ "$status" -eq 0 ]

    local captured="$BATS_TEST_TMPDIR/gh_stdin.log"
    [ -f "$captured" ]

    # リテラル \n がコメント本文に含まれていないことを確認
    if grep -qF '\n' "$captured"; then
        echo "ERROR: Comment contains literal \\n characters:"
        cat "$captured"
        return 1
    fi
}

@test "escalate_to_manual comment contains actual newlines and markdown structure" {
    run escalate_to_manual 99 "error: build failed"
    [ "$status" -eq 0 ]

    local captured="$BATS_TEST_TMPDIR/gh_stdin.log"
    [ -f "$captured" ]

    # 実際の改行で区切られたMarkdown構造を確認
    grep -q "## 🤖 CI自動修正: エスカレーション" "$captured"
    grep -q "### 失敗サマリー" "$captured"
    grep -q "### 対応が必要な項目" "$captured"
    grep -q "error: build failed" "$captured"
    grep -q "\- \[ \] 失敗ログの確認" "$captured"
}
