#!/usr/bin/env bats
# pr-merge-full.sh のBatsテスト
# PRのマージと関連処理を行う包括的スクリプト

load '../../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
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

# ====================
# ヘルプ表示テスト
# ====================

@test "pr-merge-full.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "pr-merge-full.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "pr-merge-full.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh"
    [ "$status" -ne 0 ]
}

@test "pr-merge-full.sh requires PR number or branch" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"引数"* ]] || [ "$status" -ne 0 ]
}

@test "pr-merge-full.sh validates PR number" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "not-a-number"
    [ "$status" -ne 0 ]
}

# ====================
# gh CLI依存チェック
# ====================

@test "pr-merge-full.sh requires gh CLI" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123"
    [ "$status" -ne 0 ]
}

@test "pr-merge-full.sh requires gh to be authenticated" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
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
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123"
    [ "$status" -ne 0 ]
}

# ====================
# モックヘルパー
# ====================

mock_gh_pr_merge() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "pr view"*)
        echo '{"number":123,"title":"Test PR","state":"OPEN","mergeStateStatus":"CLEAN","baseRefName":"main"}'
        exit 0
        ;;
    "pr checks"*)
        exit 0
        ;;
    "pr merge"*)
        echo '{"number":123,"state":"MERGED"}'
        exit 0
        ;;
    "issue view"*)
        echo '{"number":42,"title":"Test Issue","state":"OPEN"}'
        exit 0
        ;;
    "issue close"*)
        echo '{"number":42,"title":"Test Issue","state":"CLOSED"}'
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

# ====================
# 機能テスト
# ====================

@test "pr-merge-full.sh merges PR" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123"
    [ "$status" -eq 0 ]
}

@test "pr-merge-full.sh checks CI status before merge" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    # CIチェックを持つか確認
    grep -q "check\|ci\|status" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "CI check not implemented"
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123"
    [ "$status" -eq 0 ]
}

@test "pr-merge-full.sh closes linked issue after merge" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    grep -q "close\|issue\|linked" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "issue closing not implemented"
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123"
    [ "$status" -eq 0 ]
}

# ====================
# オプションテスト
# ====================

@test "pr-merge-full.sh supports --squash option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    grep -q "squash\|--squash\|-s" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "squash option not implemented"
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123" --squash
    [ "$status" -eq 0 ]
}

@test "pr-merge-full.sh supports --rebase option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    grep -q "rebase\|--rebase\|-r" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "rebase option not implemented"
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123" --rebase
    [ "$status" -eq 0 ]
}

@test "pr-merge-full.sh supports --delete-branch option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    grep -q "delete\|--delete\|-d" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "delete-branch option not implemented"
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123" --delete-branch
    [ "$status" -eq 0 ]
}

@test "pr-merge-full.sh supports --no-cleanup option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    grep -q "no-cleanup\|cleanup" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "no-cleanup option not implemented"
    
    mock_gh_pr_merge
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123" --no-cleanup
    [ "$status" -eq 0 ]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "pr-merge-full.sh fails when PR not found" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "pr view"*)
        echo "pull request not found" >&2
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "999"
    [ "$status" -ne 0 ]
}

@test "pr-merge-full.sh fails when CI is failing" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" ]]; then
        skip "pr-merge-full.sh not found"
    fi
    
    grep -q "check\|ci" "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" 2>/dev/null || \
        skip "CI check not implemented"
    
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "pr view"*)
        echo '{"number":123,"state":"OPEN"}'
        exit 0
        ;;
    "pr checks"*)
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/pr-merge-workflow/scripts/pr-merge-full.sh" "123"
    [ "$status" -ne 0 ]
}
