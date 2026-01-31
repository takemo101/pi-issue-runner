#!/usr/bin/env bats
# worktree.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_WORKTREE_BASE_DIR
    
    # worktree_base_dirを一時ディレクトリに設定
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees"
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# gitのモック
mock_git_success() {
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
case "\$1" in
    "worktree")
        case "\$2" in
            "add")
                # worktreeディレクトリを作成
                if [[ "\$3" == "-b" ]]; then
                    mkdir -p "\$5" 2>/dev/null
                    echo "Created worktree at \$5"
                else
                    mkdir -p "\$3" 2>/dev/null
                    echo "Created worktree at \$3"
                fi
                exit 0
                ;;
            "remove")
                rm -rf "\$3" 2>/dev/null
                exit 0
                ;;
            "list")
                if [[ "\$3" == "--porcelain" ]]; then
                    echo "worktree /main"
                    echo "HEAD abc123"
                    echo "branch refs/heads/main"
                    echo ""
                    echo "worktree ${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
                    echo "HEAD def456"
                    echo "branch refs/heads/feature/issue-42-test"
                    echo ""
                fi
                exit 0
                ;;
        esac
        ;;
    "rev-parse")
        if [[ "\$2" == "--verify" ]]; then
            exit 1  # ブランチが存在しない
        fi
        exit 0
        ;;
    "branch")
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

mock_git_worktree_exists() {
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
case "\$1" in
    "worktree")
        case "\$2" in
            "list")
                if [[ "\$3" == "--porcelain" ]]; then
                    echo "worktree ${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
                    echo "HEAD abc123"
                    echo "branch refs/heads/feature/issue-42-test"
                    echo ""
                    echo "worktree ${BATS_TEST_TMPDIR}/.worktrees/issue-99-fix"
                    echo "HEAD def456"
                    echo "branch refs/heads/feature/issue-99-fix"
                fi
                exit 0
                ;;
            "remove")
                rm -rf "\$3" 2>/dev/null || rm -rf "\$4" 2>/dev/null
                exit 0
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# ====================
# create_worktree テスト
# ====================

@test "create_worktree creates directory" {
    mock_git_success
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    result="$(create_worktree "issue-42-test")"
    
    # パスが返されることを確認
    [[ "$result" == *"issue-42-test"* ]]
}

@test "create_worktree fails when directory exists" {
    mock_git_success
    export PATH="$MOCK_DIR:$PATH"
    
    # 既存のディレクトリを作成
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/existing-branch"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    run create_worktree "existing-branch"
    [ "$status" -ne 0 ]
}

@test "create_worktree uses custom base branch" {
    mock_git_success
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    result="$(create_worktree "issue-43-test" "develop")"
    [[ "$result" == *"issue-43-test"* ]]
}

# ====================
# remove_worktree テスト
# ====================

@test "remove_worktree removes existing worktree" {
    mock_git_worktree_exists
    export PATH="$MOCK_DIR:$PATH"
    
    # テスト用worktreeディレクトリを作成
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    run remove_worktree "${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
    [ "$status" -eq 0 ]
}

@test "remove_worktree fails for non-existent worktree" {
    mock_git_success
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    run remove_worktree "/nonexistent/path"
    [ "$status" -ne 0 ]
}

@test "remove_worktree with force option" {
    mock_git_worktree_exists
    export PATH="$MOCK_DIR:$PATH"
    
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    run remove_worktree "${BATS_TEST_TMPDIR}/.worktrees/issue-42-test" "true"
    [ "$status" -eq 0 ]
}

# ====================
# list_worktrees テスト
# ====================

@test "list_worktrees returns worktrees in base dir" {
    mock_git_worktree_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    result="$(list_worktrees)"
    [[ "$result" == *"issue-42-test"* ]]
}

@test "list_worktrees returns empty for no worktrees" {
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "worktree" && "$2" == "list" ]]; then
    echo "worktree /main"
    echo "HEAD abc123"
    echo "branch refs/heads/main"
fi
exit 0
MOCK_EOF
    chmod +x "$mock_script"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    result="$(list_worktrees)"
    [ -z "$result" ]
}

# ====================
# get_worktree_branch テスト
# ====================

@test "get_worktree_branch returns branch name" {
    # 実際のディレクトリを作成
    local worktree_dir="${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
    mkdir -p "$worktree_dir"
    
    # 正規化されたパスを取得
    local normalized_path="$(cd "$worktree_dir" && pwd -P)"
    
    # モックを作成（正規化されたパスを使用）
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    echo "worktree ${normalized_path}"
    echo "HEAD abc123"
    echo "branch refs/heads/feature/issue-42-test"
    echo ""
fi
exit 0
MOCK_EOF
    chmod +x "$mock_script"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    result="$(get_worktree_branch "$worktree_dir")"
    [ "$result" = "feature/issue-42-test" ]
}

@test "get_worktree_branch returns empty for unknown path" {
    local mock_script="$MOCK_DIR/git"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "worktree" && "$2" == "list" ]]; then
    echo "worktree /some/other/path"
    echo "HEAD abc123"
    echo "branch refs/heads/main"
    echo ""
fi
exit 0
MOCK_EOF
    chmod +x "$mock_script"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # Use run to capture potential failures
    run get_worktree_branch "/unknown/path"
    [ -z "$output" ]
}

# ====================
# find_worktree_by_issue テスト
# ====================

@test "find_worktree_by_issue finds matching worktree" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # テスト用ディレクトリを作成
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/issue-42-test"
    
    result="$(find_worktree_by_issue "42")"
    [[ "$result" == *"issue-42"* ]]
}

@test "find_worktree_by_issue returns failure for no match" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    run find_worktree_by_issue "999"
    [ "$status" -ne 0 ]
}

@test "find_worktree_by_issue handles multiple worktrees" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # 複数のworktreeディレクトリを作成
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/issue-10-first"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/issue-20-second"
    
    result="$(find_worktree_by_issue "20")"
    [[ "$result" == *"issue-20"* ]]
}

# ====================
# copy_files_to_worktree テスト
# ====================

@test "copy_files_to_worktree copies configured files" {
    export PI_RUNNER_WORKTREE_COPY_FILES=".env .env.local"
    
    # ソースファイルを作成（カレントディレクトリに）
    echo "TEST=value" > "$BATS_TEST_TMPDIR/.env"
    
    # worktreeディレクトリを作成
    local worktree_dir="${BATS_TEST_TMPDIR}/test-worktree"
    mkdir -p "$worktree_dir"
    
    # カレントディレクトリを変更してテスト
    cd "$BATS_TEST_TMPDIR"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    copy_files_to_worktree "$worktree_dir"
    
    [ -f "$worktree_dir/.env" ]
}

@test "copy_files_to_worktree handles missing files gracefully" {
    export PI_RUNNER_WORKTREE_COPY_FILES=".nonexistent"
    
    local worktree_dir="${BATS_TEST_TMPDIR}/test-worktree"
    mkdir -p "$worktree_dir"
    
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # エラーにならないことを確認
    run copy_files_to_worktree "$worktree_dir"
    [ "$status" -eq 0 ]
}

# ====================
# 統合テスト
# ====================

@test "worktree functions load without error" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # 関数が定義されていることを確認
    declare -f create_worktree > /dev/null
    declare -f remove_worktree > /dev/null
    declare -f list_worktrees > /dev/null
    declare -f find_worktree_by_issue > /dev/null
}
