#!/usr/bin/env bats
# applescript-injection.bats - AppleScript インジェクション脆弱性の回帰テスト (Issue #1078)

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeディレクトリを設定
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/notify.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
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

# ====================
# Issue #1078: AppleScript インジェクション対策
# ====================

@test "Regression #1078: open_terminal_and_attach validates session name" {
    skip_if_not_macos
    
    # セッション名に特殊文字が含まれる場合は拒否される
    run open_terminal_and_attach 'malicious"; osascript -e "do shell script \"whoami\""'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid session name"* ]]
}

@test "Regression #1078: open_terminal_and_attach rejects command injection attempt" {
    skip_if_not_macos
    
    # セッション名に埋め込まれたコマンド実行の試み
    run open_terminal_and_attach 'session; rm -rf /tmp/test'
    [ "$status" -eq 1 ]
}

@test "Regression #1078: notify_error properly escapes backslashes" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
# 引数をファイルに記録
echo "$@" > "$BATS_TEST_TMPDIR/osascript_call.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # バックスラッシュを含むエラーメッセージ
    notify_error "test-session" "1078" 'Error: path\to\file'
    
    # エスケープが正しく行われていることを確認
    local result
    result=$(cat "$BATS_TEST_TMPDIR/osascript_call.log")
    
    # エスケープされたバックスラッシュが含まれている
    [[ "$result" == *"\\\\"* ]]
}

@test "Regression #1078: notify_error properly escapes double quotes" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
echo "$@" > "$BATS_TEST_TMPDIR/osascript_call.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # ダブルクォートを含むエラーメッセージ
    notify_error "test-session" "1078" 'Error: "invalid input"'
    
    # エスケープが正しく行われていることを確認
    local result
    result=$(cat "$BATS_TEST_TMPDIR/osascript_call.log")
    
    # エスケープされたダブルクォートが含まれている
    [[ "$result" == *'\\"'* ]]
}

@test "Regression #1078: notify_error removes newlines from message" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
echo "$@" > "$BATS_TEST_TMPDIR/osascript_call.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # 改行を含むエラーメッセージ
    notify_error "test-session" "1078" $'Error:\nLine 1\nLine 2'
    
    # 改行が削除されていることを確認（スペースに置換）
    local result
    result=$(cat "$BATS_TEST_TMPDIR/osascript_call.log")
    
    # 改行文字が含まれていない
    ! [[ "$result" == *$'\n'* ]]
}

@test "Regression #1078: open_terminal_and_attach escapes script path with spaces" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
echo "$@" > "$BATS_TEST_TMPDIR/osascript_call.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    
    # スペースを含むパスのテスト用にモックattach.shを作成
    mkdir -p "$BATS_TEST_TMPDIR/path with spaces"
    cat > "$BATS_TEST_TMPDIR/path with spaces/attach.sh" << 'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/path with spaces/attach.sh"
    
    # _NOTIFY_LIB_DIRを一時的にオーバーライド
    local original_lib_dir="$_NOTIFY_LIB_DIR"
    _NOTIFY_LIB_DIR="$BATS_TEST_TMPDIR/path with spaces"
    
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # スペースを含むパスでも正しく動作する
    run open_terminal_and_attach 'valid-session-name'
    [ "$status" -eq 0 ]
    
    # 元に戻す
    _NOTIFY_LIB_DIR="$original_lib_dir"
}

@test "Regression #1078: valid session names are accepted" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    
    # モックattach.shを作成
    local mock_attach="$PROJECT_ROOT/scripts/attach.sh"
    if [[ ! -x "$mock_attach" ]]; then
        skip "attach.sh not found"
    fi
    
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # 有効なセッション名のパターン
    run open_terminal_and_attach 'pi-issue-42'
    [ "$status" -eq 0 ]
    
    run open_terminal_and_attach 'session_name_123'
    [ "$status" -eq 0 ]
    
    run open_terminal_and_attach 'valid-session-name'
    [ "$status" -eq 0 ]
    
    run open_terminal_and_attach 'UPPERCASE_SESSION'
    [ "$status" -eq 0 ]
}
