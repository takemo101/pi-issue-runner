#!/usr/bin/env bats
# github.sh のBatsテスト

load '../test_helper'

setup() {
    # 共通のtmpdirセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
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

# ====================
# ブランチ名生成テスト
# ====================

@test "issue_to_branch_name generates correct format" {
    # ghコマンドのモック
    mock_gh
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(issue_to_branch_name 42)"
    
    # issue-42-で始まることを確認
    [[ "$result" == issue-42-* ]]
}

@test "issue_to_branch_name sanitizes special characters" {
    # カスタムモック: 特殊文字を含むタイトル
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Feature: Add New Feature!","body":"","labels":[],"state":"OPEN"}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(issue_to_branch_name 42)"
    
    # 特殊文字がハイフンに変換されていることを確認
    [[ "$result" != *":"* ]]
    [[ "$result" != *"!"* ]]
    [[ "$result" == *"feature"* ]]
}

@test "issue_to_branch_name truncates long titles to 40 chars" {
    # カスタムモック: 長いタイトル
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"This is a very very very long title that should be truncated","body":"","labels":[],"state":"OPEN"}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(issue_to_branch_name 42)"
    
    # issue-42- (9文字) + タイトル部分(最大40文字) = 最大49文字
    title_part="${result#issue-42-}"
    [ ${#title_part} -le 40 ]
}

# ====================
# Issue情報取得テスト
# ====================

@test "get_issue_title returns title" {
    mock_gh
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_title 42)"
    [ "$result" = "Test Issue" ]
}

@test "get_issue_body returns body" {
    mock_gh
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_body 42)"
    [ "$result" = "Test body" ]
}

@test "get_issue_state returns state" {
    mock_gh
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_state 42)"
    [ "$result" = "OPEN" ]
}

# ====================
# サニタイズテスト
# ====================

@test "sanitize_issue_body escapes command substitution" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='Hello $(rm -rf /)'
    result="$(sanitize_issue_body "$input")"
    
    # $( が \$( にエスケープされていることを確認
    [[ "$result" == *'\$('* ]]
}

@test "sanitize_issue_body escapes backticks" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='Hello `whoami`'
    result="$(sanitize_issue_body "$input")"
    
    # バッククォートがエスケープされていることを確認
    [[ "$result" == *'\`'* ]]
}

@test "sanitize_issue_body escapes variable expansion" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='Hello ${PATH}'
    result="$(sanitize_issue_body "$input")"
    
    # ${ が \${ にエスケープされていることを確認
    [[ "$result" == *'\${'* ]]
}

@test "sanitize_issue_body returns empty for empty input" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(sanitize_issue_body "")"
    [ -z "$result" ]
}

@test "sanitize_issue_body preserves safe content" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input="This is a safe issue body with normal text."
    result="$(sanitize_issue_body "$input")"
    
    [ "$result" = "$input" ]
}

# Note: detect_dangerous_patterns does not exist in lib/github.sh
# Tests for has_dangerous_patterns are already below

# ====================
# 依存関係チェックテスト
# ====================

@test "check_jq succeeds when jq is available" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    # jqが実際にインストールされている環境でテスト
    if command -v jq &> /dev/null; then
        run check_jq
        [ "$status" -eq 0 ]
    else
        skip "jq not installed"
    fi
}

# ====================
# get_issues_created_after テスト
# ====================

@test "get_issues_created_after function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f get_issues_created_after > /dev/null
}

@test "get_issues_created_after uses gh issue list" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f get_issues_created_after)
    [[ "$func_def" == *"gh issue list"* ]]
}

@test "get_issues_created_after filters by author @me" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f get_issues_created_after)
    [[ "$func_def" == *'@me'* ]]
}

# ====================
# has_dangerous_patterns テスト
# ====================

@test "has_dangerous_patterns returns false for safe text" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns "Safe text without any special patterns"
    [ "$status" -eq 1 ]
}

@test "has_dangerous_patterns detects command substitution" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns 'Dangerous $(rm -rf /)'
    [ "$status" -eq 0 ]
}

@test "has_dangerous_patterns detects backticks" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns 'Dangerous `rm -rf /`'
    [ "$status" -eq 0 ]
}

@test "has_dangerous_patterns detects variable expansion" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns 'Dangerous ${PATH}'
    [ "$status" -eq 0 ]
}
