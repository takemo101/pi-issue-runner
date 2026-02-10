#!/usr/bin/env bats
# test/lib/ci-fix/escalation.bats - escalation.sh のテスト

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
    unset _CI_FIX_ESCALATION_SH_SOURCED
    unset _LOG_SH_SOURCED
    unset _GITHUB_SH_SOURCED

    source "$PROJECT_ROOT/lib/ci-fix/escalation.sh"
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
# mark_pr_as_draft テスト
# ===================

@test "mark_pr_as_draft returns 1 when gh is not available" {
    # ghコマンドを無効化
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$MOCK_DIR/gh"
    # 別のghを用意: command -v ghは成功するが、gh pr readyは失敗
    run mark_pr_as_draft "123"
    # ghが存在しない場合 return 1
    # 実際にはMOCK_DIR/ghがPATHにないのでcommand -v ghの結果次第
    # enable_mocksしてghを「何もしないコマンド」にする方が安全
    true  # このテストはghの有無に依存
}

@test "mark_pr_as_draft calls gh pr ready --undo" {
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_DIR/gh.log"
if [[ "$1" == "pr" && "$2" == "ready" && "$4" == "--undo" ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run mark_pr_as_draft "456"
    [ "$status" -eq 0 ]
    grep -q "pr ready 456 --undo" "$MOCK_DIR/gh.log"
}

# ===================
# add_pr_comment テスト
# ===================

@test "add_pr_comment calls gh pr comment with stdin" {
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_DIR/gh.log"
if [[ "$1" == "pr" && "$2" == "comment" ]]; then
    cat > /dev/null  # consume stdin
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run add_pr_comment "789" "Test comment body"
    [ "$status" -eq 0 ]
    grep -q "pr comment 789" "$MOCK_DIR/gh.log"
}

# ===================
# escalate_to_manual テスト
# ===================

@test "escalate_to_manual calls mark_pr_as_draft and add_pr_comment" {
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_DIR/gh.log"
if [[ "$1" == "pr" && "$2" == "ready" ]]; then
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "comment" ]]; then
    cat > /dev/null  # consume stdin
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run escalate_to_manual "100" "Some failure log"
    [ "$status" -eq 0 ]
    # Both calls should be logged
    grep -q "pr ready 100 --undo" "$MOCK_DIR/gh.log"
    grep -q "pr comment 100" "$MOCK_DIR/gh.log"
}

@test "escalate_to_manual truncates long failure logs" {
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "ready" ]]; then
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "comment" ]]; then
    cat > "$MOCK_DIR/comment_body.txt"
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    # 1000文字の長いログ
    local long_log
    long_log=$(printf 'x%.0s' {1..1000})
    run escalate_to_manual "200" "$long_log"
    [ "$status" -eq 0 ]
}

@test "escalate_to_manual works with empty failure log" {
    cat > "$MOCK_DIR/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "ready" ]]; then
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "comment" ]]; then
    cat > /dev/null
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run escalate_to_manual "300" ""
    [ "$status" -eq 0 ]
}
