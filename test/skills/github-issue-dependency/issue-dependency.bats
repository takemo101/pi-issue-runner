#!/usr/bin/env bats
# issue-dependency.sh のBatsテスト
# Issue間の依存関係を管理するスクリプト

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

@test "issue-dependency.sh --help shows usage" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "issue-dependency.sh -h shows help" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "issue-dependency.sh fails without arguments" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh"
    [ "$status" -ne 0 ]
}

@test "issue-dependency.sh requires valid command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" "invalid-cmd"
    [ "$status" -ne 0 ]
}

# ====================
# サブコマンドテスト
# ====================

@test "issue-dependency.sh supports add command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    grep -q "add\|\"add\"\|'add'" "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" 2>/dev/null || \
        skip "add command not implemented"
    
    mock_gh_issue_dependency
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" add "100" "101"
    [ "$status" -eq 0 ]
}

@test "issue-dependency.sh supports remove command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    grep -q "remove\|\"remove\"\|'remove'\|rm" "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" 2>/dev/null || \
        skip "remove command not implemented"
    
    mock_gh_issue_dependency
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" remove "100" "101"
    [ "$status" -eq 0 ]
}

@test "issue-dependency.sh supports list command" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    grep -q "list\|\"list\"\|'list'\|ls" "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" 2>/dev/null || \
        skip "list command not implemented"
    
    mock_gh_issue_dependency
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" list "100"
    [ "$status" -eq 0 ]
}

# ====================
# gh CLI依存チェック
# ====================

@test "issue-dependency.sh requires gh CLI" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    export PATH="/usr/bin:/bin"
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" add "100" "101"
    [ "$status" -ne 0 ]
}

@test "issue-dependency.sh requires gh to be authenticated" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
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
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" add "100" "101"
    [ "$status" -ne 0 ]
}

# ====================
# モックヘルパー
# ====================

mock_gh_issue_dependency() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "auth status")
        exit 0
        ;;
    "issue view"*)
        echo '{"number":100,"title":"Test Issue","state":"OPEN"}'
        exit 0
        ;;
    "issue list"*|"issue dep"*)
        echo '[{"number":101,"title":"Dependency Issue"}]'
        exit 0
        ;;
    "api"*|"graphql"*)
        echo '{"data":{}}'
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
# 依存関係追加テスト
# ====================

@test "issue-dependency.sh add validates issue numbers" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" add "invalid" "101"
    [ "$status" -ne 0 ]
}

@test "issue-dependency.sh add fails when issue not found" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
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
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" add "999" "101"
    [ "$status" -ne 0 ]
}

# ====================
# オプションテスト
# ====================

@test "issue-dependency.sh supports --repo option" {
    if [[ ! -f "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" ]]; then
        skip "issue-dependency.sh not found"
    fi
    
    grep -q "repo\|--repo\|-R" "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" 2>/dev/null || \
        skip "repo option not implemented"
    
    mock_gh_issue_dependency
    enable_mocks
    
    run "$PROJECT_ROOT/.pi/skills/github-issue-dependency/scripts/issue-dependency.sh" add "100" "101" --repo "owner/repo"
    [ "$status" -eq 0 ]
}
