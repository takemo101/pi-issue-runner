#!/usr/bin/env bats
# add-sub-issue.sh のBatsテスト
# GitHub GraphQL APIを使用してサブIssueを追加するスクリプト

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

@test "add-sub-issue.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "add-sub-issue.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "add-sub-issue.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh"
    [ "$status" -ne 0 ]
}

@test "add-sub-issue.sh fails without parent issue" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --sub "123"
    [ "$status" -ne 0 ]
}

@test "add-sub-issue.sh fails without sub issue" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "456"
    [ "$status" -ne 0 ]
}

@test "add-sub-issue.sh requires valid issue numbers" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "not-a-number" --sub "123"
    [ "$status" -ne 0 ]
}

# ====================
# gh CLI依存チェック
# ====================

@test "add-sub-issue.sh requires gh CLI" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" "parent" "child"
    [ "$status" -ne 0 ]
}

@test "add-sub-issue.sh requires gh to be authenticated" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    # gh auth statusで未認証をシミュレート
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
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "100" --sub "101"
    [ "$status" -ne 0 ]
}

# ====================
# 機能テスト
# ====================

mock_gh_graphql() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "api graphql"*)
        # GraphQL API成功をシミュレート
        echo '{"data":{"addSubIssue":{"subIssue":{"number":101}}}}'
        exit 0
        ;;
    "issue view"*)
        echo '{"number":100,"title":"Parent Issue"}'
        ;;
    *)
        echo "Mock gh: $*" >&2
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

@test "add-sub-issue.sh adds sub-issue with parent and sub options" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    mock_gh_graphql
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "100" --sub "101"
    [ "$status" -eq 0 ]
}

@test "add-sub-issue.sh accepts positional arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    grep -q "positional\|\$1\|\$2" "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" 2>/dev/null || \
        skip "positional arguments not implemented"
    
    mock_gh_graphql
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" "100" "101"
    [ "$status" -eq 0 ]
}

@test "add-sub-issue.sh outputs success message" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    mock_gh_graphql
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "100" --sub "101"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]] || [[ "$output" == *"成功"* ]] || [[ "$output" == *"added"* ]]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "add-sub-issue.sh handles API errors gracefully" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    # APIエラーをシミュレート
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "api graphql"*)
        echo '{"errors":[{"message":"API Error"}]}' >&2
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "100" --sub "101"
    [ "$status" -ne 0 ]
}

@test "add-sub-issue.sh validates parent issue exists" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    # 親Issueが存在しない場合をシミュレート
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
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "999" --sub "101"
    [ "$status" -ne 0 ]
}

# ====================
# リポジトリオプションテスト
# ====================

@test "add-sub-issue.sh supports --repo option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" ]]; then
        skip "add-sub-issue.sh not found"
    fi
    
    grep -q "repo\|--repo\|-R" "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" 2>/dev/null || \
        skip "repo option not implemented"
    
    mock_gh_graphql
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-graphql-api/scripts/add-sub-issue.sh" --parent "100" --sub "101" --repo "owner/repo"
    [ "$status" -eq 0 ]
}
