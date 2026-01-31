#!/usr/bin/env bash
# run.sh の統合テスト

# テスト用にエラーで終了しないように
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SCRIPT="$PROJECT_ROOT/scripts/run.sh"

# テストカウンター
TESTS_PASSED=0
TESTS_FAILED=0

# テスト用の一時ディレクトリ
TEST_WORKTREE_BASE=""
declare -a CLEANUP_SESSIONS
declare -a CLEANUP_DIRS
CLEANUP_SESSIONS=()
CLEANUP_DIRS=()

cleanup_test_env() {
    # tmuxセッションのクリーンアップ
    for session in "${CLEANUP_SESSIONS[@]:-}"; do
        if [[ -n "$session" ]]; then
            tmux kill-session -t "$session" 2>/dev/null || true
        fi
    done
    
    # worktreeのクリーンアップ
    for dir in "${CLEANUP_DIRS[@]:-}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            git worktree remove --force "$dir" 2>/dev/null || rm -rf "$dir"
        fi
    done
    
    if [[ -n "$TEST_WORKTREE_BASE" && -d "$TEST_WORKTREE_BASE" ]]; then
        rm -rf "$TEST_WORKTREE_BASE"
    fi
    
    # テスト用ブランチのクリーンアップ
    git branch -D "feature/issue-99998-test-run" 2>/dev/null || true
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

# ===================
# 引数パースのテスト
# ===================
echo "=== Argument parsing tests ==="

# ヘルプオプション
result=$("$RUN_SCRIPT" --help 2>&1)
exit_code=$?
assert_success "--help returns success" "$exit_code"
assert_contains "--help shows usage" "Usage:" "$result"
assert_contains "--help shows issue-number argument" "issue-number" "$result"
assert_contains "--help shows --branch option" "--branch" "$result"
assert_contains "--help shows --base option" "--base" "$result"
assert_contains "--help shows --no-attach option" "--no-attach" "$result"
assert_contains "--help shows --reattach option" "--reattach" "$result"
assert_contains "--help shows --force option" "--force" "$result"

# -h オプション
result=$("$RUN_SCRIPT" -h 2>&1)
exit_code=$?
assert_success "-h returns success" "$exit_code"
assert_contains "-h shows usage" "Usage:" "$result"

# ===================
# エラーケースのテスト
# ===================
echo ""
echo "=== Error cases tests ==="

# ghが認証されているか確認（CIでは認証されていない場合がある）
if gh auth status &>/dev/null; then
    GH_AUTHENTICATED=true
else
    GH_AUTHENTICATED=false
    echo "⊘ Skipping some tests (gh not authenticated)"
fi

# issue番号なしで実行
if [[ "$GH_AUTHENTICATED" == "true" ]]; then
    if result=$("$RUN_SCRIPT" 2>&1); then
        exit_code=0
    else
        exit_code=1
    fi
    assert_failure "run.sh without issue number fails" "$exit_code"
    assert_contains "error message mentions issue number required" "Issue number is required" "$result"
else
    echo "⊘ Skipping: error message mentions issue number required (gh not authenticated)"
fi

# 不明なオプション
if [[ "$GH_AUTHENTICATED" == "true" ]]; then
    if result=$("$RUN_SCRIPT" --unknown-option 2>&1); then
        exit_code=0
    else
        exit_code=1
    fi
    assert_failure "run.sh with unknown option fails" "$exit_code"
    assert_contains "error message mentions unknown option" "Unknown option" "$result"
else
    echo "⊘ Skipping: error message mentions unknown option (gh not authenticated)"
fi

# 複数の位置引数（2つ目の引数はエラー）
if [[ "$GH_AUTHENTICATED" == "true" ]]; then
    if result=$("$RUN_SCRIPT" 42 extra-arg 2>&1); then
        exit_code=0
    else
        exit_code=1
    fi
    assert_failure "run.sh with extra positional argument fails" "$exit_code"
    assert_contains "error message mentions unexpected argument" "Unexpected argument" "$result"
else
    echo "⊘ Skipping: error message mentions unexpected argument (gh not authenticated)"
fi

# ===================
# オプションの組み合わせテスト
# ===================
echo ""
echo "=== Option combination tests (syntax check only) ==="

# スクリプトの構文チェック
bash -n "$RUN_SCRIPT" 2>&1
exit_code=$?
assert_success "run.sh has valid bash syntax" "$exit_code"

# 各オプションが正しくパースされることを確認
# （実際の実行はモックが必要なため、ヘルプ出力で確認）

# --branch オプション
result=$("$RUN_SCRIPT" --help 2>&1)
assert_contains "--branch option documented" "--branch NAME" "$result"

# --base オプション  
assert_contains "--base option documented" "--base BRANCH" "$result"

# --pi-args オプション
assert_contains "--pi-args option documented" "--pi-args ARGS" "$result"

# ===================
# 依存関係チェックのテスト
# ===================
echo ""
echo "=== Dependency check tests ==="

# スクリプトが必要な依存関係をチェックしていることを確認
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/github.sh"
set +e  # Re-enable after source

# check_dependencies関数の存在確認
if type check_dependencies &>/dev/null; then
    echo "✓ check_dependencies function exists"
    ((TESTS_PASSED++)) || true
else
    echo "✗ check_dependencies function not found"
    ((TESTS_FAILED++)) || true
fi

# ===================
# 環境変数オーバーライドテスト
# ===================
echo ""
echo "=== Environment variable tests ==="

# 設定が環境変数で上書きできることを確認
_CONFIG_LOADED=""
export PI_RUNNER_PI_COMMAND="echo-mock-pi"
source "$PROJECT_ROOT/lib/config.sh"
load_config

result=$(get_config pi_command)
assert_equals "PI_RUNNER_PI_COMMAND overrides pi_command" "echo-mock-pi" "$result"

unset PI_RUNNER_PI_COMMAND

# ===================
# セッション名生成テスト
# ===================
echo ""
echo "=== Session name generation tests ==="

source "$PROJECT_ROOT/lib/tmux.sh"

_CONFIG_LOADED=""
export PI_RUNNER_TMUX_SESSION_PREFIX="test"
load_config

result=$(generate_session_name "123")
assert_equals "session name with custom prefix" "test-issue-123" "$result"

unset PI_RUNNER_TMUX_SESSION_PREFIX

# ===================
# モック環境での実行テスト
# ===================
echo ""
echo "=== Mock environment tests ==="

# テスト環境のセットアップ
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Skipping mock tests: not in a git repository"
else
    TEST_WORKTREE_BASE=$(mktemp -d)
    
    # piコマンドをモック化
    export PI_RUNNER_PI_COMMAND="echo"
    export PI_RUNNER_PI_ARGS="mock-pi-running"
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    export PI_RUNNER_TMUX_SESSION_PREFIX="test-run"
    export PI_RUNNER_TMUX_START_IN_SESSION="false"
    
    # ghコマンドが利用可能かチェック
    if command -v gh &>/dev/null; then
        # GitHub CLIでIssueを取得できるかテスト（認証されている場合のみ）
        if gh auth status &>/dev/null 2>&1; then
            echo "Note: GitHub CLI is authenticated, mock tests may use real data"
        else
            echo "Note: GitHub CLI is not authenticated, skipping full mock tests"
        fi
    fi
    
    # worktreeベースディレクトリが設定されていることを確認
    _CONFIG_LOADED=""
    load_config
    result=$(get_config worktree_base_dir)
    assert_equals "worktree_base_dir set for mock test" "$TEST_WORKTREE_BASE" "$result"
fi

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
