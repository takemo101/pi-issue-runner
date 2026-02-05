#!/usr/bin/env bash
# test_helper.bash - Batsテスト共通ヘルパー

# プロジェクトルートを設定
# test_helper.bashはtest/にあるので、そこから親ディレクトリがプロジェクトルート
_TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_TEST_HELPER_DIR/.." && pwd)"
export PROJECT_ROOT

# テスト用一時ディレクトリ
setup() {
    # Bats 1.5+の場合BATS_TEST_TMPDIRが自動設定される
    # それ以前の場合は手動で作成
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        BATS_TEST_TMPDIR="$(mktemp -d)"
        export BATS_TEST_TMPDIR
        export _CLEANUP_TMPDIR=1
    fi
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    
    # 元のPATHを保存
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    # PATHを復元
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    # 自分で作成したtmpdirの場合はクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# モックをPATHに追加
enable_mocks() {
    export PATH="$MOCK_DIR:$PATH"
}

# ghコマンドのモック
mock_gh() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "issue view 42 --json"*|"issue view 42 -R"*"--json"*)
        echo '{"number":42,"title":"Test Issue","body":"Test body","labels":[],"state":"OPEN","comments":[]}'
        ;;
    "issue view 999 --json"*|"issue view 999 -R"*"--json"*)
        echo "issue not found" >&2
        exit 1
        ;;
    "auth status"*)
        exit 0
        ;;
    "repo view --json nameWithOwner"*)
        echo "owner/repo"
        ;;
    *)
        echo "Mock gh: unknown command: $*" >&2
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# tmuxコマンドのモック
mock_tmux() {
    local mock_script="$MOCK_DIR/tmux"
    cat > "$mock_script" << 'MOCK_EOF'
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
MOCK_EOF
    chmod +x "$mock_script"
}

# gitコマンドのモック
mock_git() {
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "worktree")
        case "$2" in
            "add")
                # worktreeディレクトリを作成
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
        if [[ "$2" == "--show-toplevel" ]]; then
            echo "$PROJECT_ROOT"
        else
            exit 1  # ブランチが存在しない
        fi
        ;;
    "branch")
        exit 0
        ;;
    "checkout")
        exit 0
        ;;
    "fetch")
        exit 0
        ;;
    *)
        /usr/bin/git "$@"
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# piコマンドのモック
mock_pi() {
    local mock_script="$MOCK_DIR/pi"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "Mock pi called with: $*"
exit 0
MOCK_EOF
    chmod +x "$mock_script"
}

# Get timeout command (GNU timeout or gtimeout)
# Returns the command path or empty string if not available
get_timeout_cmd() {
    command -v timeout || command -v gtimeout || echo ""
}

# Require timeout command for test
# Skips test if timeout is not available
# Returns the timeout command path if available
require_timeout() {
    local cmd
    cmd=$(get_timeout_cmd)
    if [[ -z "$cmd" ]]; then
        skip "timeout command not available (install coreutils or gnu-timeout)"
    fi
    echo "$cmd"
}

# アサーションヘルパー
# 文字列が含まれているかチェック
assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo "Expected '$haystack' to contain '$needle'" >&2
        return 1
    fi
}

# 文字列が含まれていないかチェック
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo "Expected '$haystack' to not contain '$needle'" >&2
        return 1
    fi
}

# 値が空でないかチェック
assert_not_empty() {
    local value="$1"
    if [[ -n "$value" ]]; then
        return 0
    else
        echo "Expected value to not be empty" >&2
        return 1
    fi
}

# ファイルが存在するかチェック
assert_file_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        return 0
    else
        echo "Expected file '$file' to exist" >&2
        return 1
    fi
}

# ディレクトリが存在するかチェック
assert_dir_exists() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        return 0
    else
        echo "Expected directory '$dir' to exist" >&2
        return 1
    fi
}
