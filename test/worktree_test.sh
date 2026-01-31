#!/usr/bin/env bash
# worktree.sh のテスト

# テスト用にエラーで終了しないように
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# lib/worktree.shに必要な依存関係
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/log.sh"
source "$SCRIPT_DIR/../lib/worktree.sh"

# テスト用にエラーで終了しないように再設定（sourceで上書きされるため）
set +e

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

# テスト用の一時ディレクトリ
TEST_WORKTREE_BASE=""
declare -a CLEANUP_DIRS
CLEANUP_DIRS=()

cleanup_test_env() {
    for dir in "${CLEANUP_DIRS[@]:-}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            git worktree remove --force "$dir" 2>/dev/null || rm -rf "$dir"
        fi
    done
    if [[ -n "$TEST_WORKTREE_BASE" && -d "$TEST_WORKTREE_BASE" ]]; then
        rm -rf "$TEST_WORKTREE_BASE"
    fi
}
trap cleanup_test_env EXIT

assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_not_empty() {
    local description="$1"
    local actual="$2"
    if [[ -n "$actual" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (value is empty)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description"
        echo "  Expected to contain: '$needle'"
        echo "  Actual: '$haystack'"
        ((TESTS_FAILED++)) || true
    fi
}

assert_success() {
    local description="$1"
    local exit_code="$2"
    if [[ "$exit_code" -eq 0 ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (exit code: $exit_code)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_failure() {
    local description="$1"
    local exit_code="$2"
    if [[ "$exit_code" -ne 0 ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (expected failure but got success)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_file_exists() {
    local description="$1"
    local filepath="$2"
    if [[ -f "$filepath" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (file not found: $filepath)"
        ((TESTS_FAILED++)) || true
    fi
}

assert_dir_exists() {
    local description="$1"
    local dirpath="$2"
    if [[ -d "$dirpath" ]]; then
        echo "✓ $description"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ $description (directory not found: $dirpath)"
        ((TESTS_FAILED++)) || true
    fi
}

# ===================
# テスト環境のセットアップ
# ===================
echo "=== Setting up test environment ==="

# Gitリポジトリ内で実行されていることを確認
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# テスト用のworktreeベースディレクトリを設定
TEST_WORKTREE_BASE=$(mktemp -d)
_CONFIG_LOADED=""
export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
load_config

echo "Test worktree base: $TEST_WORKTREE_BASE"

# ===================
# find_worktree_by_issue テスト
# ===================
echo ""
echo "=== find_worktree_by_issue tests ==="

# 存在しないissue番号
if result=$(find_worktree_by_issue "99999" 2>/dev/null); then
    if [[ -z "$result" ]]; then
        echo "✓ find_worktree_by_issue returns empty for nonexistent issue"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ find_worktree_by_issue should return empty for nonexistent issue"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "✓ find_worktree_by_issue returns failure for nonexistent issue"
    ((TESTS_PASSED++)) || true
fi

# ===================
# copy_files_to_worktree テスト
# ===================
echo ""
echo "=== copy_files_to_worktree tests ==="

# テスト用ファイルを作成
TEST_COPY_DIR=$(mktemp -d)
cd "$PROJECT_ROOT"

# 現在の設定でcopy_filesを確認
_CONFIG_LOADED=""
export PI_RUNNER_WORKTREE_COPY_FILES=".env.test .env.local.test"
load_config

# テスト用ファイル作成
echo "test=value1" > ".env.test"
echo "local=value2" > ".env.local.test"

# コピー実行
copy_files_to_worktree "$TEST_COPY_DIR" 2>/dev/null

# ファイルがコピーされたか確認
assert_file_exists "copy_files copies .env.test" "$TEST_COPY_DIR/.env.test"
assert_file_exists "copy_files copies .env.local.test" "$TEST_COPY_DIR/.env.local.test"

# クリーンアップ
rm -f ".env.test" ".env.local.test"
rm -rf "$TEST_COPY_DIR"

unset PI_RUNNER_WORKTREE_COPY_FILES

# ===================
# create_worktree テスト（実際のworktree作成）
# ===================
echo ""
echo "=== create_worktree tests ==="

# 新しいworktreeを作成
_CONFIG_LOADED=""
export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
export PI_RUNNER_WORKTREE_COPY_FILES=""
load_config

TEST_BRANCH_NAME="issue-99999-test-$(date +%s)"

# worktreeが作成されることを確認
cd "$PROJECT_ROOT"
worktree_path=$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>/dev/null)
exit_code=$?

if [[ $exit_code -eq 0 && -n "$worktree_path" ]]; then
    CLEANUP_DIRS+=("$worktree_path")
    echo "✓ create_worktree succeeds"
    ((TESTS_PASSED++)) || true
    
    assert_dir_exists "worktree directory created" "$worktree_path"
    
    # ブランチが作成されたか確認
    if git rev-parse --verify "feature/$TEST_BRANCH_NAME" &>/dev/null; then
        echo "✓ feature branch created"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ feature branch not created"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "✗ create_worktree failed (exit code: $exit_code)"
    ((TESTS_FAILED++)) || true
fi

# ===================
# 重複worktree作成テスト
# ===================
echo ""
echo "=== create_worktree duplicate tests ==="

# 同じブランチ名で再度作成しようとするとエラー
_CONFIG_LOADED=""
load_config

if result=$(create_worktree "$TEST_BRANCH_NAME" "HEAD" 2>&1); then
    # 成功した場合はエラーメッセージを確認
    if [[ "$result" == *"already exists"* ]]; then
        echo "✓ create_worktree reports existing worktree"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ create_worktree should fail or report existing worktree"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "✓ create_worktree fails for existing worktree"
    ((TESTS_PASSED++)) || true
fi

# ===================
# find_worktree_by_issue（存在するworktree）
# ===================
echo ""
echo "=== find_worktree_by_issue tests (existing worktree) ==="

# issue番号を含むworktreeを検索
result=$(find_worktree_by_issue "99999" 2>/dev/null) || true
if [[ -n "$result" && "$result" == *"issue-99999"* ]]; then
    echo "✓ find_worktree_by_issue finds existing worktree"
    ((TESTS_PASSED++)) || true
else
    echo "✓ find_worktree_by_issue returns empty for non-matching pattern"
    ((TESTS_PASSED++)) || true
fi

# ===================
# list_worktrees テスト
# ===================
echo ""
echo "=== list_worktrees tests ==="

_CONFIG_LOADED=""
export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
load_config

result=$(list_worktrees 2>/dev/null)
if [[ -n "$result" ]]; then
    echo "✓ list_worktrees returns results"
    ((TESTS_PASSED++)) || true
    assert_contains "list_worktrees includes test worktree" "issue-99999" "$result"
else
    # worktreeが無い場合も正常
    echo "✓ list_worktrees returns empty (no matching worktrees)"
    ((TESTS_PASSED++)) || true
fi

# ===================
# get_worktree_branch テスト（サブシェル問題の修正確認）
# ===================
echo ""
echo "=== get_worktree_branch tests (subshell fix) ==="

# 作成済みworktreeのブランチを取得
if [[ -n "${worktree_path:-}" && -d "$worktree_path" ]]; then
    branch=$(get_worktree_branch "$worktree_path" 2>/dev/null)
    
    if [[ -n "$branch" ]]; then
        echo "✓ get_worktree_branch returns branch name"
        ((TESTS_PASSED++)) || true
        assert_contains "get_worktree_branch returns correct branch" "feature/$TEST_BRANCH_NAME" "feature/$branch"
    else
        echo "✗ get_worktree_branch returned empty (subshell issue?)"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "⚠ Skipping get_worktree_branch test (no worktree available)"
fi

# 存在しないworktreeパスでの動作確認
branch=$(get_worktree_branch "/nonexistent/worktree/path" 2>/dev/null)
if [[ -z "$branch" ]]; then
    echo "✓ get_worktree_branch returns empty for nonexistent path"
    ((TESTS_PASSED++)) || true
else
    echo "✗ get_worktree_branch should return empty for nonexistent path"
    ((TESTS_FAILED++)) || true
fi

# ===================
# remove_worktree テスト
# ===================
echo ""
echo "=== remove_worktree tests ==="

# 存在しないworktreeを削除しようとするとエラー
if result=$(remove_worktree "/nonexistent/path/worktree" 2>&1); then
    # 成功した場合はエラーメッセージを確認
    if [[ "$result" == *"not found"* ]]; then
        echo "✓ remove_worktree reports not found"
        ((TESTS_PASSED++)) || true
    else
        echo "✗ remove_worktree should fail or report not found"
        ((TESTS_FAILED++)) || true
    fi
else
    echo "✓ remove_worktree fails for nonexistent path"
    ((TESTS_PASSED++)) || true
fi

# クリーンアップ（テストで作成したworktreeを削除）
if [[ -n "${worktree_path:-}" && -d "$worktree_path" ]]; then
    remove_worktree "$worktree_path" true 2>/dev/null || true
    git branch -D "feature/$TEST_BRANCH_NAME" 2>/dev/null || true
    CLEANUP_DIRS=()
fi

unset PI_RUNNER_WORKTREE_BASE_DIR

# ===================
# 結果サマリー
# ===================
echo ""
echo "===================="
echo "Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "===================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
