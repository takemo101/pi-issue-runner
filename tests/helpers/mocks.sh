#!/usr/bin/env bash
# mocks.sh - テスト用モック関数

# モックディレクトリを作成
setup_mocks() {
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

# ghコマンドのモック
mock_gh() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    "issue view 42 --json"*)
        echo '{"number":42,"title":"Test Issue","body":"Test body","labels":[],"state":"OPEN"}'
        ;;
    "auth status"*)
        exit 0
        ;;
    "repo view --json nameWithOwner -q .nameWithOwner"*)
        echo "owner/repo"
        ;;
    *)
        echo "Mock gh: unknown command: $*" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$mock_script"
}

# tmuxコマンドのモック
mock_tmux() {
    local mock_script="$MOCK_DIR/tmux"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 1  # セッションが存在しない
        ;;
    "new-session")
        exit 0
        ;;
    "kill-session")
        exit 0
        ;;
    "list-sessions")
        echo ""
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$mock_script"
}

# gitコマンドのモック（部分的）
mock_git_worktree() {
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "worktree")
        case "$2" in
            "add")
                mkdir -p "$4" 2>/dev/null || mkdir -p "$3"
                exit 0
                ;;
            "remove")
                exit 0
                ;;
            "list")
                echo ""
                ;;
        esac
        ;;
    "rev-parse")
        exit 1  # ブランチが存在しない
        ;;
    "branch")
        exit 0
        ;;
    *)
        /usr/bin/git "$@"
        ;;
esac
EOF
    chmod +x "$mock_script"
}

# モックをクリーンアップ
cleanup_mocks() {
    rm -rf "$MOCK_DIR"
}
