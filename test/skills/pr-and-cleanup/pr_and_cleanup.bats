#!/usr/bin/env bats
# pr_and_cleanup.sh のBatsテスト
# PR作成とクリーンアップを行うスクリプト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export ORIGINAL_PATH="$PATH"
    
    # Gitリポジトリをセットアップ
    export TEST_REPO="$BATS_TEST_TMPDIR/test_repo"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > file.txt
    git add file.txt
    git commit -m "Initial commit" -q
    
    # worktreeディレクトリを作成
    mkdir -p "$TEST_REPO/.worktrees/issue-42-test"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプ表示テスト
# ====================

@test "pr_and_cleanup.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "pr_and_cleanup.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "pr_and_cleanup.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh"
    [ "$status" -ne 0 ]
}

@test "pr_and_cleanup.sh requires issue number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"引数"* ]] || [ "$status" -ne 0 ]
}

@test "pr_and_cleanup.sh validates issue number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "not-a-number"
    [ "$status" -ne 0 ]
}

# ====================
# gh CLI依存チェック
# ====================

@test "pr_and_cleanup.sh requires gh CLI" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42"
    [ "$status" -ne 0 ]
}

@test "pr_and_cleanup.sh requires gh to be authenticated" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        echo "not authenticated" >&2
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42"
    [ "$status" -ne 0 ]
}

# ====================
# 機能テスト
# ====================

mock_gh_pr_and_cleanup() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "issue view"*)
        echo '{"number":42,"title":"Test Issue","body":"Test body","state":"OPEN"}'
        exit 0
        ;;
    "pr create"*)
        echo "https://github.com/owner/repo/pull/123"
        exit 0
        ;;
    "pr view"*)
        echo '{"number":123,"state":"OPEN"}'
        exit 0
        ;;
    *)
        echo "Mock gh: $*" >&2
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

@test "pr_and_cleanup.sh creates PR for issue" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    mock_gh_pr_and_cleanup
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42"
    [ "$status" -eq 0 ]
}

@test "pr_and_cleanup.sh outputs PR URL" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    mock_gh_pr_and_cleanup
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42"
    [ "$status" -eq 0 ]
    [[ "$output" == *"github.com"* ]] || [[ "$output" == *"pull"* ]]
}

# ====================
# オプションテスト
# ====================

@test "pr_and_cleanup.sh supports --base option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    grep -q "base\|--base\|-B" "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" 2>/dev/null || \
        skip "base option not implemented"
    
    mock_gh_pr_and_cleanup
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42" --base "main"
    [ "$status" -eq 0 ]
}

@test "pr_and_cleanup.sh supports --cleanup option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    grep -q "cleanup\|--cleanup\|-c" "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" 2>/dev/null || \
        skip "cleanup option not implemented"
    
    mock_gh_pr_and_cleanup
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42" --cleanup
    [ "$status" -eq 0 ]
}

@test "pr_and_cleanup.sh supports --draft option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    grep -q "draft\|--draft\|-d" "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" 2>/dev/null || \
        skip "draft option not implemented"
    
    mock_gh_pr_and_cleanup
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42" --draft
    [ "$status" -eq 0 ]
}

@test "pr_and_cleanup.sh supports --repo option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    grep -q "repo\|--repo\|-R" "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" 2>/dev/null || \
        skip "repo option not implemented"
    
    mock_gh_pr_and_cleanup
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "42" --repo "owner/repo"
    [ "$status" -eq 0 ]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "pr_and_cleanup.sh fails when issue not found" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" ]]; then
        skip "pr_and_cleanup.sh not found"
    fi
    
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "issue view"*)
        echo "issue not found" >&2
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-and-cleanup/scripts/pr_and_cleanup.sh" "999"
    [ "$status" -ne 0 ]
}
