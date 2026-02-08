#!/usr/bin/env bats
# notify.sh のBatsテスト

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
# get_status_dir テスト
# ====================

@test "get_status_dir returns correct path" {
    result="$(get_status_dir)"
    [ "$result" = "$TEST_WORKTREE_DIR/.status" ]
}

# ====================
# init_status_dir テスト
# ====================

@test "init_status_dir creates directory" {
    rm -rf "$TEST_WORKTREE_DIR/.status"
    init_status_dir
    [ -d "$TEST_WORKTREE_DIR/.status" ]
}

# ====================
# save_status テスト
# ====================

@test "save_status creates status file" {
    save_status "42" "running" "pi-issue-42"
    [ -f "$TEST_WORKTREE_DIR/.status/42.json" ]
}

@test "save_status writes issue number" {
    save_status "42" "running" "pi-issue-42"
    grep -q '"issue": 42' "$TEST_WORKTREE_DIR/.status/42.json"
}

@test "save_status writes status" {
    save_status "42" "running" "pi-issue-42"
    grep -q '"status": "running"' "$TEST_WORKTREE_DIR/.status/42.json"
}

@test "save_status writes session" {
    save_status "42" "running" "pi-issue-42"
    grep -q '"session": "pi-issue-42"' "$TEST_WORKTREE_DIR/.status/42.json"
}

@test "save_status with error writes error_message" {
    save_status "43" "error" "pi-issue-43" "Test error message"
    [ -f "$TEST_WORKTREE_DIR/.status/43.json" ]
    grep -q '"error_message":' "$TEST_WORKTREE_DIR/.status/43.json"
    grep -q 'Test error message' "$TEST_WORKTREE_DIR/.status/43.json"
}

# ====================
# load_status テスト
# ====================

@test "load_status returns valid JSON" {
    save_status "42" "running" "pi-issue-42"
    json="$(load_status "42")"
    echo "$json" | grep -q '"issue": 42'
}

# ====================
# get_status_value テスト
# ====================

@test "get_status_value returns running status" {
    save_status "42" "running" "pi-issue-42"
    result="$(get_status_value "42")"
    [ "$result" = "running" ]
}

@test "get_status_value returns error status" {
    save_status "43" "error" "pi-issue-43" "Test error"
    result="$(get_status_value "43")"
    [ "$result" = "error" ]
}

@test "get_status_value returns unknown for non-existent" {
    result="$(get_status_value "999")"
    [ "$result" = "unknown" ]
}

# ====================
# get_error_message テスト
# ====================

@test "get_error_message returns error message" {
    save_status "43" "error" "pi-issue-43" "Test error message"
    result="$(get_error_message "43")"
    # トリムして比較
    result_trimmed="${result%% }"
    [ "$result_trimmed" = "Test error message" ]
}

@test "get_error_message returns empty for non-error" {
    save_status "42" "running" "pi-issue-42"
    result="$(get_error_message "42")"
    [ -z "$result" ]
}

# ====================
# remove_status テスト
# ====================

@test "remove_status removes file" {
    save_status "42" "running" "pi-issue-42"
    remove_status "42"
    result="$(get_status_value "42")"
    [ "$result" = "unknown" ]
}

# ====================
# プラットフォーム検出テスト
# ====================

@test "is_macos returns correct value on current platform" {
    if [[ "$(uname)" == "Darwin" ]]; then
        is_macos
    else
        ! is_macos
    fi
}

@test "is_linux returns correct value on current platform" {
    if [[ "$(uname)" == "Linux" ]]; then
        is_linux
    else
        ! is_linux
    fi
}

# ====================
# JSON エスケープテスト
# ====================

@test "save_status with special characters produces valid JSON" {
    save_status "44" "error" "pi-issue-44" 'Error with "quotes" and \backslash'
    
    if command -v jq &>/dev/null; then
        cat "$TEST_WORKTREE_DIR/.status/44.json" | jq . > /dev/null 2>&1
    else
        skip "jq not installed"
    fi
}

# ====================
# open_terminal_and_attach セキュリティテスト
# ====================

@test "open_terminal_and_attach rejects invalid session names with quotes" {
    skip_if_not_macos
    
    # ダブルクォートを含むセッション名は拒否される
    run open_terminal_and_attach 'pi-issue-"42"'
    [ "$status" -eq 1 ]
}

@test "open_terminal_and_attach rejects invalid session names with backslash" {
    skip_if_not_macos
    
    # バックスラッシュを含むセッション名は拒否される
    run open_terminal_and_attach 'pi-issue-\42'
    [ "$status" -eq 1 ]
}

@test "open_terminal_and_attach rejects invalid session names with special characters" {
    skip_if_not_macos
    
    # 特殊文字を含むセッション名は拒否される
    run open_terminal_and_attach 'pi-issue-42; rm -rf /'
    [ "$status" -eq 1 ]
}

@test "open_terminal_and_attach accepts valid session names" {
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
    
    # 有効なセッション名は受け入れられる
    run open_terminal_and_attach 'pi-issue-42'
    [ "$status" -eq 0 ]
    
    run open_terminal_and_attach 'valid_session-name_123'
    [ "$status" -eq 0 ]
}

# ====================
# notify_error エスケープテスト
# ====================

@test "notify_error escapes backslashes in error messages" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
# 引数をログに記録
echo "$@" > "$BATS_TEST_TMPDIR/osascript.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # バックスラッシュを含むエラーメッセージ
    notify_error "test-session" "42" 'Error with \ backslash'
    
    # エスケープされたバックスラッシュが含まれているか確認
    grep -q '\\\\' "$BATS_TEST_TMPDIR/osascript.log" || {
        cat "$BATS_TEST_TMPDIR/osascript.log"
        false
    }
}

@test "notify_error escapes double quotes in error messages" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
echo "$@" > "$BATS_TEST_TMPDIR/osascript.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # ダブルクォートを含むエラーメッセージ
    notify_error "test-session" "42" 'Error with "quotes"'
    
    # エスケープされたダブルクォートが含まれているか確認
    grep -q '\\"' "$BATS_TEST_TMPDIR/osascript.log" || {
        cat "$BATS_TEST_TMPDIR/osascript.log"
        false
    }
}

@test "notify_error removes newlines from error messages" {
    skip_if_not_macos
    
    # モックosascriptを作成
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/osascript" << 'SCRIPT'
#!/bin/bash
echo "$@" > "$BATS_TEST_TMPDIR/osascript.log"
exit 0
SCRIPT
    chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    
    # 改行を含むエラーメッセージ
    notify_error "test-session" "42" $'Error with\nnewline'
    
    # 改行が含まれていないことを確認（スペースに置換される）
    ! grep -q $'\n' "$BATS_TEST_TMPDIR/osascript.log" || {
        cat "$BATS_TEST_TMPDIR/osascript.log"
        false
    }
}

# ====================
# handle_complete / handle_error テスト
# ====================
# Note: handle_complete and handle_error were removed from lib/notify.sh in Issue #883/#904
# These functions are now implemented in scripts/watch-session.sh
# Plan deletion functionality is tested via watch-session.sh integration tests
