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

@test "sanitize_issue_body escapes process substitution input" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='test <(cat /etc/passwd) test'
    result="$(sanitize_issue_body "$input")"
    
    # <( が \<( にエスケープされていることを確認
    [[ "$result" == *'\<'* ]]
}

@test "sanitize_issue_body escapes process substitution output" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='test >(cat) test'
    result="$(sanitize_issue_body "$input")"
    
    # >( が \>( にエスケープされていることを確認
    [[ "$result" == *'\>'* ]]
}

@test "sanitize_issue_body escapes arithmetic expansion" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='test $((1+1)) test'
    result="$(sanitize_issue_body "$input")"
    
    # $(( が \$(( にエスケープされていることを確認
    [[ "$result" == *'\$((1+1))'* ]]
}

@test "sanitize_issue_body escapes all dangerous patterns" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    input='$(cmd) `backtick` ${var} <(input) >(output) $((1+2))'
    result="$(sanitize_issue_body "$input")"
    
    # 全てのパターンがエスケープされていることを確認
    [[ "$result" == *'\$(' ]]
    [[ "$result" == *'\`' ]]
    [[ "$result" == *'\${' ]]
    [[ "$result" == *'\<(' ]]
    [[ "$result" == *'\>(' ]]
    [[ "$result" == *'\$((1+2))'* ]]
}

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
    # Function now uses gh_args array with "issue list" command
    [[ "$func_def" == *"issue list"* ]]
}

@test "get_issues_created_after filters by author @me" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f get_issues_created_after)
    [[ "$func_def" == *'@me'* ]]
}

@test "get_issues_created_after accepts optional label parameter" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f get_issues_created_after)
    # Check that the function accepts a third parameter for label
    [[ "$func_def" == *'label="${3:-}"'* ]]
}

@test "get_issues_created_after adds --label option when label is provided" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f get_issues_created_after)
    [[ "$func_def" == *'--label "$label"'* ]]
}

# ====================
# generate_session_label テスト
# ====================

@test "generate_session_label function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f generate_session_label > /dev/null
}

@test "generate_session_label returns label with pi-runner prefix" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(generate_session_label)"
    [[ "$result" == pi-runner-* ]]
}

@test "generate_session_label returns label in correct format" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(generate_session_label)"
    # Format: pi-runner-YYYYMMDD-HHMMSS
    [[ "$result" =~ ^pi-runner-[0-9]{8}-[0-9]{6}$ ]]
}

# ====================
# create_label_if_not_exists テスト
# ====================

@test "create_label_if_not_exists function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f create_label_if_not_exists > /dev/null
}

@test "create_label_if_not_exists uses gh label create" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f create_label_if_not_exists)
    [[ "$func_def" == *'gh label create'* ]]
}

@test "create_label_if_not_exists uses gh label list to check existence" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    func_def=$(declare -f create_label_if_not_exists)
    [[ "$func_def" == *'gh label list'* ]]
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

@test "has_dangerous_patterns detects process substitution input" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns 'Dangerous <(cat /etc/passwd)'
    [ "$status" -eq 0 ]
}

@test "has_dangerous_patterns detects process substitution output" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns 'Dangerous >(cat)'
    [ "$status" -eq 0 ]
}

@test "has_dangerous_patterns detects arithmetic expansion" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    run has_dangerous_patterns 'Dangerous $((1+1))'
    [ "$status" -eq 0 ]
}

# ====================
# get_issue_comments テスト
# ====================

@test "get_issue_comments function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f get_issue_comments > /dev/null
}

@test "get_issue_comments returns empty for issue without comments" {
    # カスタムモック: コメントなし
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test Issue","body":"Test body","labels":[],"state":"OPEN","comments":[]}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_comments 42)"
    [ -z "$result" ]
}

@test "get_issue_comments returns formatted comments" {
    # カスタムモック: コメントあり
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test Issue","body":"Test body","labels":[],"state":"OPEN","comments":[{"author":{"login":"user1"},"body":"First comment","createdAt":"2024-01-31T10:00:00Z"},{"author":{"login":"user2"},"body":"Second comment","createdAt":"2024-01-31T11:00:00Z"}]}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_comments 42)"
    
    # コメントが含まれていることを確認
    [[ "$result" == *"@user1"* ]]
    [[ "$result" == *"First comment"* ]]
    [[ "$result" == *"@user2"* ]]
    [[ "$result" == *"Second comment"* ]]
    [[ "$result" == *"2024-01-31"* ]]
}

@test "get_issue_comments respects max_comments limit" {
    # カスタムモック: 5件のコメント
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test","body":"","labels":[],"state":"OPEN","comments":[{"author":{"login":"u1"},"body":"c1","createdAt":"2024-01-01T00:00:00Z"},{"author":{"login":"u2"},"body":"c2","createdAt":"2024-01-02T00:00:00Z"},{"author":{"login":"u3"},"body":"c3","createdAt":"2024-01-03T00:00:00Z"},{"author":{"login":"u4"},"body":"c4","createdAt":"2024-01-04T00:00:00Z"},{"author":{"login":"u5"},"body":"c5","createdAt":"2024-01-05T00:00:00Z"}]}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    # max_comments=2の場合、最新2件のみ
    result="$(get_issue_comments 42 2)"
    
    # 古いコメント(c1, c2, c3)は含まれない
    [[ "$result" != *"@u1"* ]]
    [[ "$result" != *"@u2"* ]]
    [[ "$result" != *"@u3"* ]]
    # 最新2件(c4, c5)は含まれる
    [[ "$result" == *"@u4"* ]]
    [[ "$result" == *"@u5"* ]]
}

@test "get_issue_comments returns all comments when max_comments is 0" {
    # カスタムモック: 3件のコメント
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test","body":"","labels":[],"state":"OPEN","comments":[{"author":{"login":"u1"},"body":"c1","createdAt":"2024-01-01T00:00:00Z"},{"author":{"login":"u2"},"body":"c2","createdAt":"2024-01-02T00:00:00Z"},{"author":{"login":"u3"},"body":"c3","createdAt":"2024-01-03T00:00:00Z"}]}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    # max_comments=0の場合、全件取得
    result="$(get_issue_comments 42 0)"
    
    [[ "$result" == *"@u1"* ]]
    [[ "$result" == *"@u2"* ]]
    [[ "$result" == *"@u3"* ]]
}

@test "get_issue_comments sanitizes dangerous patterns in comments" {
    # カスタムモック: 危険なパターンを含むコメント
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
echo '{"number":42,"title":"Test","body":"","labels":[],"state":"OPEN","comments":[{"author":{"login":"attacker"},"body":"Run this: $(rm -rf /)","createdAt":"2024-01-01T00:00:00Z"}]}'
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_comments 42)"
    
    # コマンド置換がエスケープされていることを確認
    [[ "$result" == *'\$('* ]]
}

# ====================
# format_comments_section テスト
# ====================

@test "format_comments_section function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f format_comments_section > /dev/null
}

@test "format_comments_section returns empty for empty input" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(format_comments_section "")"
    [ -z "$result" ]
    
    result="$(format_comments_section "[]")"
    [ -z "$result" ]
    
    result="$(format_comments_section "null")"
    [ -z "$result" ]
}

@test "format_comments_section formats single comment correctly" {
    source "$PROJECT_ROOT/lib/github.sh"
    
    comments_json='[{"author":{"login":"testuser"},"body":"Test comment body","createdAt":"2024-03-15T09:30:00Z"}]'
    result="$(format_comments_section "$comments_json")"
    
    [[ "$result" == *"### @testuser (2024-03-15)"* ]]
    [[ "$result" == *"Test comment body"* ]]
}

# ====================
# get_issue_blockers テスト
# ====================

@test "get_issue_blockers function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f get_issue_blockers > /dev/null
}

@test "get_issue_blockers returns blockers list" {
    # GraphQL APIモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"基盤機能","state":"OPEN"},{"number":39,"title":"依存タスク","state":"CLOSED"}]}}}}}'
else
    echo "Mock gh: unknown command: $*" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_blockers 42)"
    
    # OPENとCLOSEDの両方が含まれる（jqの出力は空白を含む）
    [[ "$result" == *'"number": 38'* ]]
    [[ "$result" == *'"number": 39'* ]]
    [[ "$result" == *'"state": "OPEN"'* ]]
    [[ "$result" == *'"state": "CLOSED"'* ]]
}

@test "get_issue_blockers returns empty array when no blockers" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
else
    echo "Mock gh: unknown command: $*" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    result="$(get_issue_blockers 42)"
    
    # 空配列が返される
    [ "$result" = "[]" ]
}

@test "get_issue_blockers returns empty array on API error" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"errors":[{"message":"Issue not found"}]}' >&2
    exit 1
else
    echo "Mock gh: unknown command: $*" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    # エラー時はreturn 1だが、空配列を出力する
    run get_issue_blockers 999
    
    # エラー時も空配列が返される
    [ "$output" = "[]" ]
    [ "$status" -eq 1 ]
}

@test "get_issue_blockers requires jq" {
    # jqがない場合のテスト - jqをモックして失敗させる
    cat > "$MOCK_DIR/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "jq not found" >&2
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/jq"
    enable_mocks
    
    # ghは通常通り動作させる
    mock_gh
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    run get_issue_blockers 42
    [ "$status" -eq 1 ]
}

# ====================
# check_issue_blocked テスト
# ====================

@test "check_issue_blocked function exists" {
    source "$PROJECT_ROOT/lib/github.sh"
    declare -f check_issue_blocked > /dev/null
}

@test "check_issue_blocked returns 1 when OPEN blockers exist" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"基盤機能","state":"OPEN"}]}}}}}'
else
    echo "Mock gh: unknown command: $*" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    run check_issue_blocked 42
    
    # OPENブロッカーがあるのでreturn 1
    [ "$status" -eq 1 ]
    # OPENブロッカー情報が出力される（jqの出力は空白を含む）
    [[ "$output" == *'"number": 38'* ]]
    [[ "$output" == *'"state": "OPEN"'* ]]
}

@test "check_issue_blocked returns 0 when all blockers are CLOSED" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":38,"title":"基盤機能","state":"CLOSED"}]}}}}}'
else
    echo "Mock gh: unknown command: $*" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    run check_issue_blocked 42
    
    # 全てCLOSEDなのでreturn 0
    [ "$status" -eq 0 ]
}

@test "check_issue_blocked returns 0 when no blockers" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
    exit 0
elif [[ "$1" == "repo" && "$2" == "view" ]]; then
    echo '{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
else
    echo "Mock gh: unknown command: $*" >&2
    exit 1
fi
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    run check_issue_blocked 42
    
    # ブロッカーがないのでreturn 0
    [ "$status" -eq 0 ]
}

@test "check_issue_blocked returns 1 when get_issue_blockers fails" {
    # get_issue_blockersが失敗するケース
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "repo view --json owner,name"*)
        exit 1
        ;;
    *)
        echo "Mock gh: unknown command: $*" >&2
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    enable_mocks
    
    source "$PROJECT_ROOT/lib/github.sh"
    
    run check_issue_blocked 42
    
    # ブロッカー取得失敗時もreturn 1
    [ "$status" -eq 1 ]
}
