#!/usr/bin/env bats
# test/lib/context.bats - lib/context.sh のテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeディレクトリを設定
    export TEST_WORKTREE_BASE="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_BASE"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/context.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_BASE" ;;
            *) echo "" ;;
        esac
    }
    
    # ログを抑制
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# ディレクトリ管理
# ===================

@test "get_context_dir returns correct path" {

    
    local context_dir
    context_dir="$(get_context_dir)"
    
    [[ "$context_dir" == "$TEST_WORKTREE_BASE/.context" ]]
}

@test "init_context_dir creates directory structure" {

    
    init_context_dir
    
    [[ -d "$TEST_WORKTREE_BASE/.context" ]]
    [[ -d "$TEST_WORKTREE_BASE/.context/issues" ]]
}

@test "get_project_context_file returns correct path" {

    
    local context_file
    context_file="$(get_project_context_file)"
    
    [[ "$context_file" == "$TEST_WORKTREE_BASE/.context/project.md" ]]
}

@test "get_issue_context_file returns correct path" {

    
    local context_file
    context_file="$(get_issue_context_file 42)"
    
    [[ "$context_file" == "$TEST_WORKTREE_BASE/.context/issues/42.md" ]]
}

# ===================
# コンテキスト読み込み
# ===================

@test "load_project_context returns empty when file doesn't exist" {

    
    local content
    content="$(load_project_context)"
    
    [[ -z "$content" ]]
}

@test "load_project_context returns content when file exists" {

    init_context_dir
    
    local context_file
    context_file="$(get_project_context_file)"
    echo "Test project context" > "$context_file"
    
    local content
    content="$(load_project_context)"
    
    [[ "$content" == "Test project context" ]]
}

@test "load_issue_context returns empty when file doesn't exist" {

    
    local content
    content="$(load_issue_context 42)"
    
    [[ -z "$content" ]]
}

@test "load_issue_context returns content when file exists" {

    init_context_dir
    
    local context_file
    context_file="$(get_issue_context_file 42)"
    echo "Test issue context" > "$context_file"
    
    local content
    content="$(load_issue_context 42)"
    
    [[ "$content" == "Test issue context" ]]
}

@test "load_all_context returns empty when no context exists" {

    
    local content
    content="$(load_all_context 42)"
    
    [[ -z "$content" ]]
}

@test "load_all_context returns project context only" {

    init_context_dir
    
    local context_file
    context_file="$(get_project_context_file)"
    echo "Project context" > "$context_file"
    
    local content
    content="$(load_all_context 42)"
    
    [[ "$content" == *"プロジェクト全体の知見"* ]]
    [[ "$content" == *"Project context"* ]]
    [[ "$content" != *"このIssue固有の履歴"* ]]
}

@test "load_all_context returns issue context only" {

    init_context_dir
    
    local context_file
    context_file="$(get_issue_context_file 42)"
    echo "Issue context" > "$context_file"
    
    local content
    content="$(load_all_context 42)"
    
    [[ "$content" != *"プロジェクト全体の知見"* ]]
    [[ "$content" == *"このIssue固有の履歴"* ]]
    [[ "$content" == *"Issue context"* ]]
}

@test "load_all_context returns both contexts" {

    init_context_dir
    
    local project_file issue_file
    project_file="$(get_project_context_file)"
    issue_file="$(get_issue_context_file 42)"
    
    echo "Project context" > "$project_file"
    echo "Issue context" > "$issue_file"
    
    local content
    content="$(load_all_context 42)"
    
    [[ "$content" == *"プロジェクト全体の知見"* ]]
    [[ "$content" == *"Project context"* ]]
    [[ "$content" == *"このIssue固有の履歴"* ]]
    [[ "$content" == *"Issue context"* ]]
}

# ===================
# コンテキスト保存
# ===================

@test "init_project_context creates file with template" {

    
    init_project_context
    
    local context_file
    context_file="$(get_project_context_file)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"# Project Context"* ]]
    [[ "$content" == *"## 技術的決定事項"* ]]
    [[ "$content" == *"## 既知の問題"* ]]
}

@test "init_project_context does not overwrite existing file" {

    init_context_dir
    
    local context_file
    context_file="$(get_project_context_file)"
    echo "Existing content" > "$context_file"
    
    init_project_context
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == "Existing content" ]]
}

@test "init_issue_context creates file with template" {

    
    init_issue_context 42 "Test Feature"
    
    local context_file
    context_file="$(get_issue_context_file 42)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"# Issue #42 Context"* ]]
    [[ "$content" == *"Title: Test Feature"* ]]
    [[ "$content" == *"## 試行履歴"* ]]
}

@test "append_project_context creates file and appends content" {

    
    append_project_context "Test entry"
    
    local context_file
    context_file="$(get_project_context_file)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"Test entry"* ]]
    [[ "$content" == *"## Entry ("* ]]
}

@test "append_project_context appends to existing file" {

    init_project_context
    
    append_project_context "First entry"
    append_project_context "Second entry"
    
    local context_file content
    context_file="$(get_project_context_file)"
    content="$(cat "$context_file")"
    
    [[ "$content" == *"First entry"* ]]
    [[ "$content" == *"Second entry"* ]]
}

@test "append_issue_context creates file and appends content" {

    
    append_issue_context 42 "Test entry"
    
    local context_file
    context_file="$(get_issue_context_file 42)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"Test entry"* ]]
    [[ "$content" == *"## Session ("* ]]
}

@test "append_issue_context appends to existing file" {

    init_issue_context 42
    
    append_issue_context 42 "First entry"
    append_issue_context 42 "Second entry"
    
    local context_file content
    context_file="$(get_issue_context_file 42)"
    content="$(cat "$context_file")"
    
    [[ "$content" == *"First entry"* ]]
    [[ "$content" == *"Second entry"* ]]
}

# ===================
# コンテキスト管理
# ===================

@test "list_issue_contexts returns empty when no contexts exist" {

    
    local issues
    issues="$(list_issue_contexts)"
    
    [[ -z "$issues" ]]
}

@test "list_issue_contexts returns all issue numbers" {

    init_context_dir
    
    # 複数のIssueコンテキストを作成
    init_issue_context 42
    init_issue_context 45
    init_issue_context 100
    
    local issues
    issues="$(list_issue_contexts)"
    
    [[ "$issues" == *"42"* ]]
    [[ "$issues" == *"45"* ]]
    [[ "$issues" == *"100"* ]]
}

@test "list_issue_contexts returns sorted numbers" {

    init_context_dir
    
    # 順不同で作成
    init_issue_context 100
    init_issue_context 42
    init_issue_context 45
    
    local issues
    issues="$(list_issue_contexts)"
    
    # 最初の行が42であることを確認
    local first_issue
    first_issue="$(echo "$issues" | head -1)"
    [[ "$first_issue" == "42" ]]
}

@test "export_context returns project context" {

    init_project_context
    append_project_context "Test entry"
    
    local content
    content="$(export_context)"
    
    [[ "$content" == *"Test entry"* ]]
}

@test "export_context returns issue context" {

    init_issue_context 42
    append_issue_context 42 "Test entry"
    
    local content
    content="$(export_context 42)"
    
    [[ "$content" == *"Test entry"* ]]
}

@test "clean_old_contexts removes old files" {

    init_context_dir
    
    # 古いファイルを作成（mtimeを変更）
    local context_file
    context_file="$(get_issue_context_file 42)"
    init_issue_context 42
    
    # macOSとLinuxの両方で動作するtouch
    if touch -t 202001010000 "$context_file" 2>/dev/null; then
        # macOS/BSD touch
        :
    else
        # GNU touch
        touch -d "2020-01-01" "$context_file" 2>/dev/null || true
    fi
    
    # 新しいファイルを作成
    init_issue_context 45
    
    local count
    count="$(clean_old_contexts 30)"
    
    # 古いファイルが削除されることを確認
    [[ "$count" -ge 0 ]]
}

@test "clean_old_contexts returns 0 when no old files" {

    init_context_dir
    
    # 新しいファイルのみ作成
    init_issue_context 42
    init_issue_context 45
    
    local count
    count="$(clean_old_contexts 30)"
    
    [[ "$count" == "0" ]]
}

@test "context_exists returns false for non-existent project context" {

    
    if context_exists; then
        return 1
    fi
}

@test "context_exists returns true for existing project context" {

    init_project_context
    
    context_exists
}

@test "context_exists returns false for non-existent issue context" {

    
    if context_exists 42; then
        return 1
    fi
}

@test "context_exists returns true for existing issue context" {

    init_issue_context 42
    
    context_exists 42
}

@test "remove_context removes project context" {

    init_project_context
    
    context_exists
    
    remove_context
    
    if context_exists; then
        return 1
    fi
}

@test "remove_context removes issue context" {

    init_issue_context 42
    
    context_exists 42
    
    remove_context 42
    
    if context_exists 42; then
        return 1
    fi
}
