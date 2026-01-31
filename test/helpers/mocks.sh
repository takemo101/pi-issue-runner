#!/usr/bin/env bash
# mocks.sh - テスト用モック関数

# モックディレクトリを作成
setup_mocks() {
    export MOCK_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

# ghコマンドのモック（ファイルベース - レガシー互換）
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

# ===================
# 関数ベースのghモック（認証なし環境向け）
# ===================

# モック状態フラグ
_MOCK_GH_ENABLED=false

# ghモックを有効化（関数ベース）
# Usage: mock_gh_function
mock_gh_function() {
    _MOCK_GH_ENABLED=true
    # 元のghコマンドを保存
    if command -v gh &>/dev/null && [[ "$(type -t gh)" != "function" ]]; then
        _ORIGINAL_GH_PATH="$(command -v gh)"
    fi
    # gh関数を定義（インライン実装）
    gh() {
        case "$1 $2" in
            "auth status")
                echo "✓ Logged in to github.com as mock-user"
                return 0
                ;;
            "issue view")
                local issue_number="$3"
                if [[ -n "$issue_number" && "$issue_number" =~ ^[0-9]+$ ]]; then
                    if [[ "$4" == "--json" ]]; then
                        echo "{\"number\":$issue_number,\"title\":\"Mock Issue #$issue_number\",\"body\":\"Mock body for issue $issue_number\",\"labels\":[],\"state\":\"OPEN\"}"
                    else
                        echo "Mock Issue #$issue_number"
                        echo "Mock body for issue $issue_number"
                    fi
                    return 0
                fi
                echo "Mock gh: issue view requires issue number" >&2
                return 1
                ;;
            "repo view")
                if [[ "$3" == "--json" ]]; then
                    echo "mock-owner/mock-repo"
                else
                    echo "mock-owner/mock-repo"
                fi
                return 0
                ;;
            "pr create")
                echo "https://github.com/mock-owner/mock-repo/pull/1"
                return 0
                ;;
            "pr merge")
                echo "✓ Merged pull request"
                return 0
                ;;
            "pr checks")
                echo "All checks passed"
                return 0
                ;;
            *)
                echo "Mock gh: $*" >&2
                return 0
                ;;
        esac
    }
    export -f gh
    export _MOCK_GH_ENABLED
}

# ghモックを無効化
# Usage: unmock_gh_function
unmock_gh_function() {
    _MOCK_GH_ENABLED=false
    unset -f gh 2>/dev/null || true
    unset -f _mock_gh_function 2>/dev/null || true
    export _MOCK_GH_ENABLED
}

# 環境変数に基づいてモックを自動設定
# Usage: auto_mock_gh
# 戻り値: 0=認証済み/モック有効, 1=認証なし
auto_mock_gh() {
    # USE_MOCK_GH=trueの場合は常にモックを使用
    if [[ "${USE_MOCK_GH:-false}" == "true" ]]; then
        mock_gh_function
        return 0
    fi
    
    # ghが認証されているか確認
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        # 認証済み - モック不要
        return 0
    else
        # 未認証 - モックを有効化
        mock_gh_function
        return 0
    fi
}

# モック状態を確認
# Usage: is_gh_mocked
is_gh_mocked() {
    [[ "${_MOCK_GH_ENABLED:-false}" == "true" ]]
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
