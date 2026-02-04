#!/usr/bin/env bats
# test/scripts/context.bats - scripts/context.sh のテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeディレクトリを設定
    export TEST_WORKTREE_BASE="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_BASE"
    
    # 環境変数でworktreeベースディレクトリを上書き（設定ファイルより優先）
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_BASE"
    
    # 設定の再読み込みを強制
    unset _CONFIG_LOADED
    
    # プロジェクトルートに移動
    cd "$PROJECT_ROOT"
    
    # ログレベルを設定（INFOレベルでテストの出力確認ができるように）
    export LOG_LEVEL="INFO"
}

# テスト間で状態を共有しないように、各テスト後にクリーンアップ
teardown() {
    # テストで作成されたコンテキストをクリーンアップ
    if [[ -d "${TEST_WORKTREE_BASE:-}" ]]; then
        rm -rf "$TEST_WORKTREE_BASE"
    fi
    
    # 設定のキャッシュをクリア
    unset _CONFIG_LOADED
    
    # Bats標準のteardownを呼び出す（test_helper.bashのteardown）
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# ヘルプとエラー
# ===================

@test "context.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/context.sh" --help
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"show"* ]]
    [[ "$output" == *"add"* ]]
}

@test "context.sh shows help with no arguments" {
    run "$PROJECT_ROOT/scripts/context.sh"
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "context.sh shows error for invalid subcommand" {
    run "$PROJECT_ROOT/scripts/context.sh" invalid-command
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown subcommand"* ]]
}

# ===================
# show サブコマンド
# ===================

@test "context.sh show displays issue context" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_issue_context 42
    append_issue_context 42 "Test content"
    
    run "$PROJECT_ROOT/scripts/context.sh" show 42
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test content"* ]]
}

@test "context.sh show shows warning when context doesn't exist" {

    
    run "$PROJECT_ROOT/scripts/context.sh" show 999
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"No context found"* ]]
}

@test "context.sh show requires issue number" {

    
    run "$PROJECT_ROOT/scripts/context.sh" show
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"Issue number is required"* ]]
}

# ===================
# show-project サブコマンド
# ===================

@test "context.sh show-project displays project context" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_project_context
    append_project_context "Test project content"
    
    run "$PROJECT_ROOT/scripts/context.sh" show-project
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test project content"* ]]
}

@test "context.sh show-project shows warning when context doesn't exist" {

    
    run "$PROJECT_ROOT/scripts/context.sh" show-project
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"No project context found"* ]]
}

# ===================
# add サブコマンド
# ===================

@test "context.sh add appends to issue context" {

    
    run "$PROJECT_ROOT/scripts/context.sh" add 42 "New entry"
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added context"* ]]
    
    # コンテキストファイルを確認
    source "$PROJECT_ROOT/lib/context.sh"
    local context_file
    context_file="$(get_issue_context_file 42)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"New entry"* ]]
}

@test "context.sh add requires issue number and text" {

    
    run "$PROJECT_ROOT/scripts/context.sh" add
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "context.sh add requires text" {

    
    run "$PROJECT_ROOT/scripts/context.sh" add 42
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "context.sh add supports multi-word text" {

    
    run "$PROJECT_ROOT/scripts/context.sh" add 42 "This is a multi-word entry"
    
    [ "$status" -eq 0 ]
    
    source "$PROJECT_ROOT/lib/context.sh"
    local content
    content="$(load_issue_context 42)"
    
    [[ "$content" == *"This is a multi-word entry"* ]]
}

# ===================
# add-project サブコマンド
# ===================

@test "context.sh add-project appends to project context" {

    
    run "$PROJECT_ROOT/scripts/context.sh" add-project "New project entry"
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added context"* ]]
    
    # コンテキストファイルを確認
    source "$PROJECT_ROOT/lib/context.sh"
    local context_file
    context_file="$(get_project_context_file)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"New project entry"* ]]
}

@test "context.sh add-project requires text" {

    
    run "$PROJECT_ROOT/scripts/context.sh" add-project
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

# ===================
# list サブコマンド
# ===================

@test "context.sh list shows all issues with context" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_issue_context 42
    init_issue_context 45
    init_issue_context 100
    
    run "$PROJECT_ROOT/scripts/context.sh" list
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"#42"* ]]
    [[ "$output" == *"#45"* ]]
    [[ "$output" == *"#100"* ]]
}

@test "context.sh list shows message when no contexts exist" {

    
    run "$PROJECT_ROOT/scripts/context.sh" list
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"No issue contexts found"* ]]
}

# ===================
# export サブコマンド
# ===================

@test "context.sh export outputs issue context" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_issue_context 42
    append_issue_context 42 "Export test"
    
    run "$PROJECT_ROOT/scripts/context.sh" export 42
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Export test"* ]]
}

@test "context.sh export outputs project context without issue number" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_project_context
    append_project_context "Project export test"
    
    run "$PROJECT_ROOT/scripts/context.sh" export
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project export test"* ]]
}

@test "context.sh export shows error when context doesn't exist" {

    
    run "$PROJECT_ROOT/scripts/context.sh" export 999
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"No context found"* ]]
}

# ===================
# init サブコマンド
# ===================

@test "context.sh init creates issue context" {

    
    run "$PROJECT_ROOT/scripts/context.sh" init 42 "Test Feature"
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialized"* ]]
    
    source "$PROJECT_ROOT/lib/context.sh"
    local context_file
    context_file="$(get_issue_context_file 42)"
    
    [[ -f "$context_file" ]]
    
    local content
    content="$(cat "$context_file")"
    
    [[ "$content" == *"Test Feature"* ]]
}

@test "context.sh init requires issue number" {

    
    run "$PROJECT_ROOT/scripts/context.sh" init
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "context.sh init shows warning when context already exists" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_issue_context 42
    
    run "$PROJECT_ROOT/scripts/context.sh" init 42
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

# ===================
# init-project サブコマンド
# ===================

@test "context.sh init-project creates project context" {

    
    run "$PROJECT_ROOT/scripts/context.sh" init-project
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialized"* ]]
    
    source "$PROJECT_ROOT/lib/context.sh"
    local context_file
    context_file="$(get_project_context_file)"
    
    [[ -f "$context_file" ]]
}

@test "context.sh init-project shows warning when context already exists" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_project_context
    
    run "$PROJECT_ROOT/scripts/context.sh" init-project
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

# ===================
# clean サブコマンド
# ===================

@test "context.sh clean removes old contexts" {

    source "$PROJECT_ROOT/lib/context.sh"
    
    init_context_dir
    
    # 古いファイルを作成
    local context_file
    context_file="$(get_issue_context_file 42)"
    init_issue_context 42
    
    # mtimeを変更（古くする）
    if touch -t 202001010000 "$context_file" 2>/dev/null; then
        :
    else
        touch -d "2020-01-01" "$context_file" 2>/dev/null || true
    fi
    
    run "$PROJECT_ROOT/scripts/context.sh" clean --days 30
    
    [ "$status" -eq 0 ]
}

@test "context.sh clean accepts --days option" {

    
    run "$PROJECT_ROOT/scripts/context.sh" clean --days 60
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"60 days"* ]]
}

@test "context.sh clean shows error for invalid option" {

    
    run "$PROJECT_ROOT/scripts/context.sh" clean --invalid
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
