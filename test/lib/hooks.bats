#!/usr/bin/env bats
# hooks.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用ワークディレクトリを作成
    export TEST_WORKDIR="$BATS_TEST_TMPDIR/workdir"
    mkdir -p "$TEST_WORKDIR"
    cd "$TEST_WORKDIR"
    
    # ステータスディレクトリを設定
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # ログレベルを抑制
    export LOG_LEVEL="ERROR"
    
    # 設定のリセット
    export _CONFIG_LOADED=""
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ヘルパー: config.shのget_configをオーバーライド
override_get_config() {
    # 設定を読み込み直す（テスト用設定ファイルを使用）
    export _CONFIG_LOADED=""
    load_config "$TEST_WORKDIR/.pi-runner.yaml" 2>/dev/null || true
}

# ヘルパー: notify.shの関数をモック
mock_notify() {
    notify_success() {
        echo "NOTIFY_SUCCESS: $1 $2"
    }
    
    notify_error() {
        echo "NOTIFY_ERROR: $1 $2 $3"
    }
    
    is_macos() {
        return 1  # 常にfalseを返す
    }
}

# ====================
# get_hook テスト
# ====================

@test "get_hook returns empty when no config file exists" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    
    result="$(get_hook "on_success")"
    [ -z "$result" ]
}

@test "get_hook returns hook value from config file" {
    # 設定ファイルを作成
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "success hook"
  on_error: ./hooks/on-error.sh
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    
    result="$(get_hook "on_success")"
    [ "$result" = 'echo "success hook"' ]
}

@test "get_hook returns script path from config file" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_error: ./hooks/on-error.sh
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    
    result="$(get_hook "on_error")"
    [ "$result" = "./hooks/on-error.sh" ]
}

@test "get_hook returns empty for undefined hook" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "success"
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    
    result="$(get_hook "on_start")"
    [ -z "$result" ]
}

# ====================
# _expand_hook_template テスト
# ====================

@test "_expand_hook_template expands issue_number" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(_expand_hook_template 'Issue #{{issue_number}} completed' '42' '' '' '' '' '' '')"
    [ "$result" = "Issue #42 completed" ]
}

@test "_expand_hook_template expands multiple variables" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(_expand_hook_template 'Issue #{{issue_number}} on {{branch_name}}' '42' 'My Title' 'session-42' 'feature/issue-42' '/path' '' '0')"
    [ "$result" = "Issue #42 on feature/issue-42" ]
}

@test "_expand_hook_template expands error_message" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(_expand_hook_template 'Error: {{error_message}}' '42' '' '' '' '' 'Test error' '1')"
    [ "$result" = "Error: Test error" ]
}

@test "_expand_hook_template expands all variables" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    template='{{issue_number}}|{{issue_title}}|{{session_name}}|{{branch_name}}|{{worktree_path}}|{{error_message}}|{{exit_code}}'
    result="$(_expand_hook_template "$template" '42' 'My Title' 'pi-42' 'feature/issue-42' '/worktrees/42' 'oops' '1')"
    [ "$result" = "42|My Title|pi-42|feature/issue-42|/worktrees/42|oops|1" ]
}

# ====================
# run_hook テスト（デフォルト動作）
# ====================

@test "run_hook calls default on_success notification when no hook defined" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"NOTIFY_SUCCESS"* ]]
}

@test "run_hook calls default on_error notification when no hook defined" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_error" "42" "pi-42" "" "" "Test error" "1" "")"
    [[ "$result" == *"NOTIFY_ERROR"* ]]
}

@test "run_hook does nothing for on_start when no hook defined" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_start" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" != *"NOTIFY"* ]]
}

@test "run_hook does nothing for on_cleanup when no hook defined" {
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_cleanup" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" != *"NOTIFY"* ]]
}

# ====================
# run_hook テスト（インラインコマンド）
# ====================

@test "run_hook executes inline command" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "INLINE_HOOK_EXECUTED"
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"INLINE_HOOK_EXECUTED"* ]]
}

@test "run_hook expands template in inline command" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "Issue {{issue_number}} done"
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"Issue 42 done"* ]]
}

# ====================
# run_hook テスト（スクリプトファイル）
# ====================

@test "run_hook executes script file" {
    mkdir -p "$TEST_WORKDIR/hooks"
    cat > "$TEST_WORKDIR/hooks/on-success.sh" << 'EOF'
#!/bin/bash
echo "SCRIPT_HOOK_EXECUTED"
echo "Issue: $PI_ISSUE_NUMBER"
EOF
    chmod +x "$TEST_WORKDIR/hooks/on-success.sh"
    
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << EOF
hooks:
  on_success: $TEST_WORKDIR/hooks/on-success.sh
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"SCRIPT_HOOK_EXECUTED"* ]]
    [[ "$result" == *"Issue: 42"* ]]
}

@test "run_hook sets environment variables" {
    mkdir -p "$TEST_WORKDIR/hooks"
    cat > "$TEST_WORKDIR/hooks/test-env.sh" << 'EOF'
#!/bin/bash
echo "NUM:$PI_ISSUE_NUMBER"
echo "SESSION:$PI_SESSION_NAME"
echo "BRANCH:$PI_BRANCH_NAME"
echo "PATH:$PI_WORKTREE_PATH"
echo "ERROR:$PI_ERROR_MESSAGE"
echo "EXIT:$PI_EXIT_CODE"
EOF
    chmod +x "$TEST_WORKDIR/hooks/test-env.sh"
    
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << EOF
hooks:
  on_error: $TEST_WORKDIR/hooks/test-env.sh
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    result="$(run_hook "on_error" "42" "pi-42" "feature/issue-42" "/worktrees/42" "oops" "1" "Test Title")"
    [[ "$result" == *"NUM:42"* ]]
    [[ "$result" == *"SESSION:pi-42"* ]]
    [[ "$result" == *"BRANCH:feature/issue-42"* ]]
    [[ "$result" == *"PATH:/worktrees/42"* ]]
    [[ "$result" == *"ERROR:oops"* ]]
    [[ "$result" == *"EXIT:1"* ]]
}

# ====================
# run_hook テスト（エラーハンドリング）
# ====================

@test "run_hook continues on hook failure" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: false
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Should not fail even if hook exits with error
    run run_hook "on_success" "42" "pi-42" "" "" "" "0" ""
    [ "$status" -eq 0 ]
}

# ====================
# 空のhook設定テスト
# ====================

@test "run_hook with empty value disables hook" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: ""
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Empty hook means no action, should use default behavior
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    # With empty string, it should fall through to default
    [[ "$result" == *"NOTIFY_SUCCESS"* ]]
}
