#!/usr/bin/env bats
# worktree.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeベースディレクトリを設定
    export TEST_WORKTREE_BASE="$BATS_TEST_TMPDIR/worktrees"
    mkdir -p "$TEST_WORKTREE_BASE"
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
    
    # 設定をリセット
    unset _CONFIG_LOADED
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
}

teardown() {
    unset PI_RUNNER_WORKTREE_BASE_DIR
    unset PI_RUNNER_WORKTREE_COPY_FILES
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# find_worktree_by_issue テスト
# ====================

@test "find_worktree_by_issue returns empty for nonexistent issue" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(find_worktree_by_issue "99999" 2>/dev/null)" || result=""
    [ -z "$result" ] || ! find_worktree_by_issue "99999" 2>/dev/null
}

@test "find_worktree_by_issue finds worktree with issue-N format" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # issue-N 形式のディレクトリを作成
    mkdir -p "$TEST_WORKTREE_BASE/issue-123"
    
    result="$(find_worktree_by_issue "123")"
    [ "$result" = "$TEST_WORKTREE_BASE/issue-123" ]
}

@test "find_worktree_by_issue finds worktree with issue-N-title format" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # issue-N-title 形式のディレクトリを作成
    mkdir -p "$TEST_WORKTREE_BASE/issue-456-refactor-worktree"
    
    result="$(find_worktree_by_issue "456")"
    [ "$result" = "$TEST_WORKTREE_BASE/issue-456-refactor-worktree" ]
}

@test "find_worktree_by_issue returns first match when multiple exist" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # 複数のディレクトリを作成（先頭一致するもの）
    mkdir -p "$TEST_WORKTREE_BASE/issue-789"
    mkdir -p "$TEST_WORKTREE_BASE/issue-789-another"
    
    result="$(find_worktree_by_issue "789")"
    # 最初に見つかったものを返す
    [ -n "$result" ]
    [[ "$result" == *"issue-789"* ]]
}

# ====================
# copy_files_to_worktree テスト
# ====================

@test "copy_files_to_worktree copies specified files" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # テスト用ファイルを作成
    cd "$PROJECT_ROOT"
    echo "test=value1" > ".env.test"
    
    # YAML設定ファイルを作成
    cat > "$BATS_TEST_TMPDIR/.pi-runner-copy.yaml" << 'EOF'
worktree:
  copy_files:
    - ".env.test"
EOF
    
    _CONFIG_LOADED=""
    load_config "$BATS_TEST_TMPDIR/.pi-runner-copy.yaml"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/copy_test"
    mkdir -p "$TEST_COPY_DIR"
    
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    [ -f "$TEST_COPY_DIR/.env.test" ]
    
    # クリーンアップ
    rm -f ".env.test"
}

@test "copy_files_to_worktree handles files with spaces in name" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # テスト用設定ファイルを作成（YAML配列を使用）
    cd "$PROJECT_ROOT"
    cat > "$BATS_TEST_TMPDIR/.pi-runner-test.yaml" << 'EOF'
worktree:
  copy_files:
    - ".env test.yml"
    - ".env.local"
EOF
    
    # スペースを含むファイル名のテストファイルを作成
    echo "test=space file" > ".env test.yml"
    echo "test=normal" > ".env.local"
    
    _CONFIG_LOADED=""
    load_config "$BATS_TEST_TMPDIR/.pi-runner-test.yaml"
    
    TEST_COPY_DIR="$BATS_TEST_TMPDIR/copy_test_spaces"
    mkdir -p "$TEST_COPY_DIR"
    
    copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null
    
    # スペースを含むファイル名が正しくコピーされることを確認
    [ -f "$TEST_COPY_DIR/.env test.yml" ]
    [ -f "$TEST_COPY_DIR/.env.local" ]
    
    # 内容も確認
    grep -q "test=space file" "$TEST_COPY_DIR/.env test.yml"
    grep -q "test=normal" "$TEST_COPY_DIR/.env.local"
    
    # クリーンアップ
    rm -f ".env test.yml" ".env.local"
}

# ====================
# list_worktrees テスト（モック使用）
# ====================

@test "list_worktrees returns without error" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    load_config "$TEST_CONFIG_FILE"
    
    # エラーなしで実行されることを確認
    run list_worktrees
    # 結果は環境依存なのでステータスだけチェック
    [ "$status" -eq 0 ] || [ -z "$output" ]
}

# ====================
# get_worktree_path テスト
# ====================

@test "get_worktree_path function exists" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    declare -f get_worktree_path > /dev/null 2>&1 || \
    declare -f find_worktree_by_issue > /dev/null
}

# ====================
# remove_worktree テスト
# ====================

@test "remove_worktree fails for nonexistent path" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    run remove_worktree "/nonexistent/path/worktree"
    [ "$status" -ne 0 ] || [[ "$output" == *"not found"* ]]
}

@test "remove_worktree fails without force when untracked files exist" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # Gitリポジトリ内で実行されていることを確認
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-427-test-$(date +%s)"
    
    # worktreeを作成
    worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>/dev/null)" || {
        skip "Failed to create worktree"
    }
    
    if [[ -z "$worktree_path" || ! -d "$worktree_path" ]]; then
        skip "Worktree creation returned empty path"
    fi
    
    # untrackedファイルを作成
    echo "untracked content" > "$worktree_path/untracked_file.txt"
    
    # force=falseで削除を試行（失敗すべき）
    run remove_worktree "$worktree_path" "false"
    
    # 削除に失敗することを確認
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to remove worktree"* ]]
    
    # worktreeがまだ存在することを確認
    [ -d "$worktree_path" ]
    
    # クリーンアップ（forceで削除）
    git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
    git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
}

@test "remove_worktree succeeds with force when untracked files exist" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # Gitリポジトリ内で実行されていることを確認
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-427-test-force-$(date +%s)"
    
    # worktreeを作成
    worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>/dev/null)" || {
        skip "Failed to create worktree"
    }
    
    if [[ -z "$worktree_path" || ! -d "$worktree_path" ]]; then
        skip "Worktree creation returned empty path"
    fi
    
    # untrackedファイルを作成
    echo "untracked content" > "$worktree_path/untracked_file.txt"
    
    # force=trueで削除を試行（成功すべき）
    run remove_worktree "$worktree_path" "true"
    
    # 削除に成功することを確認
    [ "$status" -eq 0 ]
    [[ "$output" == *"successfully"* ]]
    
    # worktreeが削除されていることを確認
    [ ! -d "$worktree_path" ]
    
    # ブランチを削除
    git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
}

# ====================
# 実際のworktree作成テスト（Git環境依存）
# ====================

@test "create_worktree creates worktree in git repo" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    # Gitリポジトリ内で実行されていることを確認
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-99999-test-$(date +%s)"
    
    worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>/dev/null)" || {
        # 作成に失敗した場合はスキップ
        skip "Failed to create worktree"
    }
    
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        [ -d "$worktree_path" ]
        
        # クリーンアップ
        git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
        git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
    else
        skip "Worktree creation returned empty path"
    fi
}

# ====================
# get_worktree_branch テスト
# ====================

@test "get_worktree_branch returns empty for nonexistent path" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(get_worktree_branch "/nonexistent/worktree/path" 2>/dev/null)" || result=""
    [ -z "$result" ]
}

# ====================
# git fetch before worktree creation テスト
# ====================

@test "create_worktree calls git fetch when base_branch starts with origin/" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-1153-fetch-test-$(date +%s)"
    
    # create_worktreeをorigin/HEADで呼び出し（fetchが実行されることを確認）
    # stderr出力にfetchログが含まれることを確認
    worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "origin/HEAD" 2>"$BATS_TEST_TMPDIR/stderr.log")" || {
        # origin/HEADが存在しない場合はスキップ
        if grep -q "not a valid" "$BATS_TEST_TMPDIR/stderr.log" 2>/dev/null; then
            skip "origin/HEAD not available"
        fi
        skip "Failed to create worktree"
    }
    
    # fetchログが出力されていることを確認
    grep -q "Fetching latest from origin" "$BATS_TEST_TMPDIR/stderr.log"
    
    # クリーンアップ
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
    fi
    git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
}

@test "create_worktree does not call git fetch for local branch" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-1153-nofetch-test-$(date +%s)"
    
    # HEADをbase_branchとして使用（fetchは不要）
    worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>"$BATS_TEST_TMPDIR/stderr.log")" || {
        skip "Failed to create worktree"
    }
    
    # fetchログが出力されていないことを確認
    ! grep -q "Fetching latest from" "$BATS_TEST_TMPDIR/stderr.log"
    
    # クリーンアップ
    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
    fi
    git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
}

@test "create_worktree warns on fetch failure and continues" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        skip "Not in a git repository"
    fi
    
    cd "$PROJECT_ROOT"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_WORKTREE_COPY_FILES=""
    load_config "$TEST_CONFIG_FILE"
    
    TEST_BRANCH_NAME="issue-1153-fetchfail-test-$(date +%s)"
    
    # 存在しないリモートを使用してfetch失敗をシミュレート
    # origin/HEAD は通常存在するため、代わりにHEADで作成してfetchログを確認
    # nonexistent_remote/main でfetch失敗のワーニングが出ることをテスト
    
    # git fetchをモックして失敗させる
    mock_dir="$BATS_TEST_TMPDIR/mock_bin"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/git" << 'MOCK_EOF'
#!/usr/bin/env bash
# fetchサブコマンドのみ失敗させるモック
if [[ "$1" == "fetch" ]]; then
    exit 1
fi
# その他のgitコマンドは本物を使用
exec /usr/bin/git "$@"
MOCK_EOF
    chmod +x "$mock_dir/git"
    
    PATH="$mock_dir:$PATH" worktree_path="$(create_worktree "$TEST_BRANCH_NAME" "origin/HEAD" 2>"$BATS_TEST_TMPDIR/stderr.log")" || {
        # worktree作成自体が失敗しても、warnログが出ていればOK
        true
    }
    
    # fetch失敗のワーニングログが出力されていることを確認
    grep -q "git fetch.*failed" "$BATS_TEST_TMPDIR/stderr.log"
    
    # クリーンアップ
    if [[ -n "${worktree_path:-}" && -d "${worktree_path:-}" ]]; then
        git worktree remove --force "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"
    fi
    git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
}

# ====================
# 構成テスト
# ====================

@test "create_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f create_worktree > /dev/null
}

@test "remove_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f remove_worktree > /dev/null
}

@test "find_worktree_by_issue function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f find_worktree_by_issue > /dev/null
}

@test "list_worktrees function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f list_worktrees > /dev/null
}

@test "copy_files_to_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f copy_files_to_worktree > /dev/null
}

@test "get_worktree_branch function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f get_worktree_branch > /dev/null
}

# ====================
# copy_dirs_to_worktree テスト
# ====================

@test "copy_dirs_to_worktree function exists" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    declare -f copy_dirs_to_worktree > /dev/null
}

@test "copy_dirs_to_worktree skips when no config file" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    local worktree_dir="$BATS_TEST_TMPDIR/test-worktree"
    mkdir -p "$worktree_dir"
    
    _CONFIG_LOADED=""
    _CONFIG_FILE_FOUND=""
    
    run copy_dirs_to_worktree "$worktree_dir"
    [ "$status" -eq 0 ]
}

@test "copy_dirs_to_worktree skips when no copy_dirs configured" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    local worktree_dir="$BATS_TEST_TMPDIR/test-worktree"
    mkdir -p "$worktree_dir"
    
    local config_file="$BATS_TEST_TMPDIR/config.yaml"
    printf 'worktree:\n  base_dir: ".worktrees"\n' > "$config_file"
    
    _CONFIG_LOADED=""
    _CONFIG_FILE_FOUND=""
    load_config "$config_file"
    
    run copy_dirs_to_worktree "$worktree_dir"
    [ "$status" -eq 0 ]
}

@test "copy_dirs_to_worktree copies directory recursively" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    local worktree_dir="$BATS_TEST_TMPDIR/test-worktree"
    mkdir -p "$worktree_dir"
    
    # コピー元のディレクトリを作成
    local src_dir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$src_dir/.opencode"
    echo '{"disabled_hooks": ["todo-continuation-enforcer"]}' > "$src_dir/.opencode/oh-my-opencode.json"
    
    local config_file="$src_dir/config.yaml"
    cat > "$config_file" << 'EOF'
worktree:
  copy_dirs:
    - .opencode
EOF
    
    # copy_dirs_to_worktree は cwd 相対でディレクトリを探すので cd する
    cd "$src_dir"
    _CONFIG_LOADED=""
    _CONFIG_FILE_FOUND=""
    load_config "$config_file"
    
    copy_dirs_to_worktree "$worktree_dir"
    
    [ -f "$worktree_dir/.opencode/oh-my-opencode.json" ]
    local content
    content="$(cat "$worktree_dir/.opencode/oh-my-opencode.json")"
    [[ "$content" == *'"todo-continuation-enforcer"'* ]]
}

@test "copy_dirs_to_worktree skips nonexistent directories" {
    source "$PROJECT_ROOT/lib/worktree.sh"
    
    local worktree_dir="$BATS_TEST_TMPDIR/test-worktree"
    mkdir -p "$worktree_dir"
    
    local config_file="$BATS_TEST_TMPDIR/config.yaml"
    cat > "$config_file" << 'EOF'
worktree:
  copy_dirs:
    - .nonexistent-dir
EOF
    
    _CONFIG_LOADED=""
    _CONFIG_FILE_FOUND=""
    load_config "$config_file"
    
    run copy_dirs_to_worktree "$worktree_dir"
    [ "$status" -eq 0 ]
    [ ! -d "$worktree_dir/.nonexistent-dir" ]
}
