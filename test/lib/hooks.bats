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
    
    # Enable inline hooks for this test
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"INLINE_HOOK_EXECUTED"* ]]
}

@test "run_hook uses environment variables in inline command" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Issue $PI_ISSUE_NUMBER done"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Enable inline hooks for this test
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
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

# ====================
# セキュリティテスト
# ====================

@test "run_hook blocks inline command when PI_RUNNER_ALLOW_INLINE_HOOKS is not set (default: false)" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "INLINE_EXECUTED_42"
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Do NOT set PI_RUNNER_ALLOW_INLINE_HOOKS (default is now false)
    unset PI_RUNNER_ALLOW_INLINE_HOOKS
    
    # Enable WARN level logging to capture the warning message
    export LOG_LEVEL="WARN"
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "" 2>&1)"
    
    # Should show warning that inline hooks are disabled
    [[ "$result" == *"Inline hook commands are disabled"* ]]
    # The hook command text appears in the warning, but should NOT be executed as output
    # Check that it's only in the warning line, not as actual execution output
    [[ "$result" == *"Hook: echo"*"INLINE_EXECUTED_42"* ]]  # Present in warning
    # Count lines - should only have 3 warning lines, no execution output
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    [ "$line_count" -eq 3 ]
}

@test "run_hook blocks inline command when PI_RUNNER_ALLOW_INLINE_HOOKS is false" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "INLINE_EXECUTED_43"
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=false
    
    # Enable WARN level logging to capture the message
    export LOG_LEVEL="WARN"
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "" 2>&1)"
    [[ "$result" == *"disabled"* ]]
    # Check that the echo command was NOT executed by filtering out log lines
    filtered=$(echo "$result" | grep -v "^\[" || true)
    [[ -z "$filtered" ]]
}

@test "run_hook allows inline command when PI_RUNNER_ALLOW_INLINE_HOOKS is true" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: echo "INLINE_ALLOWED"
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"INLINE_ALLOWED"* ]]
}

@test "run_hook always allows script file hooks regardless of PI_RUNNER_ALLOW_INLINE_HOOKS" {
    mkdir -p "$TEST_WORKDIR/hooks"
    cat > "$TEST_WORKDIR/hooks/test.sh" << 'EOF'
#!/bin/bash
echo "SCRIPT_EXECUTED"
EOF
    chmod +x "$TEST_WORKDIR/hooks/test.sh"
    
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << EOF
hooks:
  on_success: $TEST_WORKDIR/hooks/test.sh
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Do NOT set PI_RUNNER_ALLOW_INLINE_HOOKS
    unset PI_RUNNER_ALLOW_INLINE_HOOKS
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "")"
    [[ "$result" == *"SCRIPT_EXECUTED"* ]]
}

# ====================
# セキュリティテスト（コマンドインジェクション対策）
# ====================

@test "run_hook is safe from command injection via issue_title" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Processing: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    # 悪意のあるIssueタイトル
    malicious_title='Fix bug"; rm -rf /tmp/test; echo "'
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "$malicious_title")"
    
    # 環境変数として安全に渡される（文字列として扱われる）
    [[ "$result" == *'Processing: Fix bug"; rm -rf /tmp/test; echo "'* ]]
}

@test "run_hook is safe from command injection via error_message" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_error: 'echo "Error: $PI_ERROR_MESSAGE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    # 悪意のあるエラーメッセージ
    malicious_error='Error"; echo INJECTED; echo "'
    
    result="$(run_hook "on_error" "42" "pi-42" "" "" "$malicious_error" "1" "")"
    
    # 環境変数として安全に渡される
    [[ "$result" == *'Error: Error"; echo INJECTED; echo "'* ]]
    # INJECTEDが単独で出力されないことを確認（コマンドとして実行されていない）
    [[ "$(echo "$result" | grep -c "^INJECTED$" || true)" -eq 0 ]]
}

@test "run_hook is safe from command injection with backticks" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    # バッククォートを使った攻撃
    malicious_title='Test `echo BACKTICK_INJECTION` title'
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "$malicious_title")"
    
    # バッククォートがそのまま表示される（実行されない）
    [[ "$result" == *'Test `echo BACKTICK_INJECTION` title'* ]]
}

@test "run_hook is safe from command injection with dollar-parenthesis" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    # $(...)を使った攻撃
    malicious_title='Test $(echo SUBSHELL_INJECTION) title'
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "$malicious_title")"
    
    # $(...)がそのまま表示される（実行されない）
    [[ "$result" == *'Test $(echo SUBSHELL_INJECTION) title'* ]]
}

# ====================
# improve関連hookテスト
# ====================

@test "get_hook returns improve hook value from config file" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_improve_start: echo "improve started"
  on_improve_end: echo "improve ended"
  on_iteration_start: echo "iteration started"
  on_iteration_end: echo "iteration ended"
  on_review_complete: echo "review complete"
EOF

    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config

    result="$(get_hook "on_improve_start")"
    [ "$result" = 'echo "improve started"' ]

    result="$(get_hook "on_improve_end")"
    [ "$result" = 'echo "improve ended"' ]

    result="$(get_hook "on_iteration_start")"
    [ "$result" = 'echo "iteration started"' ]

    result="$(get_hook "on_iteration_end")"
    [ "$result" = 'echo "iteration ended"' ]

    result="$(get_hook "on_review_complete")"
    [ "$result" = 'echo "review complete"' ]
}

@test "run_hook sets improve-related environment variables" {
    mkdir -p "$TEST_WORKDIR/hooks"
    cat > "$TEST_WORKDIR/hooks/test-improve-env.sh" << 'EOF'
#!/bin/bash
echo "ITERATION:$PI_ITERATION"
echo "MAX_ITERATIONS:$PI_MAX_ITERATIONS"
echo "ISSUES_CREATED:$PI_ISSUES_CREATED"
echo "ISSUES_SUCCEEDED:$PI_ISSUES_SUCCEEDED"
echo "ISSUES_FAILED:$PI_ISSUES_FAILED"
echo "REVIEW_COUNT:$PI_REVIEW_ISSUES_COUNT"
EOF
    chmod +x "$TEST_WORKDIR/hooks/test-improve-env.sh"

    cat > "$TEST_WORKDIR/.pi-runner.yaml" << EOF
hooks:
  on_iteration_end: $TEST_WORKDIR/hooks/test-improve-env.sh
EOF

    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify

    result="$(run_hook "on_iteration_end" "" "" "" "" "" "0" "" "2" "5" "3" "2" "1" "")"
    [[ "$result" == *"ITERATION:2"* ]]
    [[ "$result" == *"MAX_ITERATIONS:5"* ]]
    [[ "$result" == *"ISSUES_CREATED:3"* ]]
    [[ "$result" == *"ISSUES_SUCCEEDED:2"* ]]
    [[ "$result" == *"ISSUES_FAILED:1"* ]]
}

@test "run_hook sets review_issues_count for on_review_complete" {
    mkdir -p "$TEST_WORKDIR/hooks"
    cat > "$TEST_WORKDIR/hooks/test-review-env.sh" << 'EOF'
#!/bin/bash
echo "REVIEW_COUNT:$PI_REVIEW_ISSUES_COUNT"
EOF
    chmod +x "$TEST_WORKDIR/hooks/test-review-env.sh"

    cat > "$TEST_WORKDIR/.pi-runner.yaml" << EOF
hooks:
  on_review_complete: $TEST_WORKDIR/hooks/test-review-env.sh
EOF

    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify

    result="$(run_hook "on_review_complete" "" "" "" "" "" "0" "" "1" "3" "" "" "" "7")"
    [[ "$result" == *"REVIEW_COUNT:7"* ]]
}

@test "run_hook is safe from command injection with special characters" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    export PI_RUNNER_ALLOW_INLINE_HOOKS=true
    
    # 様々な特殊文字
    malicious_title='Test; ls -la & echo "injection" | cat'
    
    result="$(run_hook "on_success" "42" "pi-42" "" "" "" "0" "$malicious_title")"
    
    # 特殊文字がそのまま表示される
    [[ "$result" == *'Test; ls -la & echo "injection" | cat'* ]]
}
