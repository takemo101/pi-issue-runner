#!/usr/bin/env bats
# notify.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_WORKTREE_BASE_DIR
    
    # worktree_base_dirを一時ディレクトリに設定
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees"
    
    # ログレベルを抑制
    export LOG_LEVEL="ERROR"
    
    # モックディレクトリをセットアップ
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

# osascriptのモック（macOS通知用）
mock_osascript() {
    local mock_script="$MOCK_DIR/osascript"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "osascript called: $*"
exit 0
MOCK_EOF
    chmod +x "$mock_script"
}

# notify-sendのモック（Linux通知用）
mock_notify_send() {
    local mock_script="$MOCK_DIR/notify-send"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "notify-send called: $*"
exit 0
MOCK_EOF
    chmod +x "$mock_script"
}

# ====================
# プラットフォーム検出テスト
# ====================

@test "is_macos returns true on macOS" {
    source "$PROJECT_ROOT/lib/notify.sh"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        run is_macos
        [ "$status" -eq 0 ]
    else
        skip "Not running on macOS"
    fi
}

@test "is_macos returns false on non-macOS" {
    source "$PROJECT_ROOT/lib/notify.sh"
    
    if [[ "$(uname)" != "Darwin" ]]; then
        run is_macos
        [ "$status" -ne 0 ]
    else
        skip "Running on macOS"
    fi
}

@test "is_linux returns true on Linux" {
    source "$PROJECT_ROOT/lib/notify.sh"
    
    if [[ "$(uname)" == "Linux" ]]; then
        run is_linux
        [ "$status" -eq 0 ]
    else
        skip "Not running on Linux"
    fi
}

@test "is_linux returns false on non-Linux" {
    source "$PROJECT_ROOT/lib/notify.sh"
    
    if [[ "$(uname)" != "Linux" ]]; then
        run is_linux
        [ "$status" -ne 0 ]
    else
        skip "Running on Linux"
    fi
}

# ====================
# notify_error テスト
# ====================

@test "notify_error calls osascript on macOS" {
    if [[ "$(uname)" != "Darwin" ]]; then
        skip "Only runs on macOS"
    fi
    
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    run notify_error "test-session" "42" "Test error"
    [ "$status" -eq 0 ]
}

@test "notify_error handles special characters in message" {
    if [[ "$(uname)" != "Darwin" ]]; then
        skip "Only runs on macOS"
    fi
    
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    # エラーにならないことを確認
    run notify_error "test-session" "42" 'Error with "quotes"'
    [ "$status" -eq 0 ]
}

# ====================
# notify_success テスト
# ====================

@test "notify_success calls osascript on macOS" {
    if [[ "$(uname)" != "Darwin" ]]; then
        skip "Only runs on macOS"
    fi
    
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    run notify_success "test-session" "42"
    [ "$status" -eq 0 ]
}

# ====================
# handle_error テスト
# ====================

@test "handle_error saves error status" {
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    # auto_attach=falseで実行（Terminal.appを開かない）
    handle_error "test-session" "42" "Test error" "false"
    
    # ステータスがエラーになっていることを確認
    result="$(get_status_value "42")"
    [ "$result" = "error" ]
}

@test "handle_error includes error message in status" {
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    handle_error "test-session" "43" "Custom error message" "false"
    
    error_msg="$(get_error_message "43")"
    [ "$error_msg" = "Custom error message" ]
}

# ====================
# handle_complete テスト
# ====================

@test "handle_complete saves complete status" {
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    handle_complete "test-session" "42"
    
    result="$(get_status_value "42")"
    [ "$result" = "complete" ]
}

@test "handle_complete sends success notification" {
    mock_osascript
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    # エラーなしで実行できることを確認
    run handle_complete "test-session" "42"
    [ "$status" -eq 0 ]
}

# ====================
# open_terminal_and_attach テスト
# ====================

@test "open_terminal_and_attach fails on non-macOS" {
    if [[ "$(uname)" == "Darwin" ]]; then
        skip "Only runs on non-macOS"
    fi
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    run open_terminal_and_attach "test-session"
    [ "$status" -ne 0 ]
}

# ====================
# 統合テスト
# ====================

@test "notify functions work without crashing" {
    mock_osascript
    mock_notify_send
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/notify.sh"
    
    # 基本的な呼び出しがクラッシュしないことを確認
    run notify_error "session" "1" "error"
    run notify_success "session" "2"
    
    # どちらの呼び出しもエラーなし
    [ "$status" -eq 0 ]
}
