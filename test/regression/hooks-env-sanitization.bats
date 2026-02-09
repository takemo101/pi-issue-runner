#!/usr/bin/env bats
# Regression test for Issue #1121: hooks.sh environment variable sanitization
# 
# This test verifies that user-controlled environment variables (PI_ISSUE_TITLE, PI_ERROR_MESSAGE)
# are properly sanitized to prevent command injection when used in inline hook commands.

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
    
    # inline hookを有効化
    export PI_RUNNER_HOOKS_ALLOW_INLINE=true
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ヘルパー: config.shのget_configをオーバーライド
override_get_config() {
    export _CONFIG_LOADED=""
    load_config "$TEST_WORKDIR/.pi-runner.yaml" 2>/dev/null || true
}

# ヘルパー: notify.shの関数をモック
mock_notify() {
    notify_success() { :; }
    notify_error() { :; }
    is_macos() { return 1; }
}

# ====================
# 回帰テスト: Issue #1121
# ====================

@test "Issue #1121: PI_ISSUE_TITLE with newline is sanitized" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Issueタイトルに改行を含む
    malicious_title=$'Fix bug\nrm -rf /tmp/test'
    
    result="$(run_hook "on_success" "1121" "pi-1121" "" "" "" "0" "$malicious_title")"
    
    # 改行が除去されていることを確認
    [[ ! "$result" =~ $'\n' ]]
    # 制御文字が除去された後の文字列が含まれる
    [[ "$result" == *"Fix bugrm -rf /tmp/test"* ]]
}

@test "Issue #1121: PI_ERROR_MESSAGE with tab is sanitized" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_error: 'echo "Error: $PI_ERROR_MESSAGE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # エラーメッセージにタブを含む
    malicious_error=$'Error\tinjection'
    
    result="$(run_hook "on_error" "1121" "pi-1121" "" "" "$malicious_error" "1" "")"
    
    # タブが除去されていることを確認
    [[ ! "$result" =~ $'\t' ]]
    # 制御文字が除去された後の文字列が含まれる
    [[ "$result" == *"Errorinjection"* ]]
}

@test "Issue #1121: PI_ISSUE_TITLE with null byte is sanitized" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # Issueタイトルにヌル文字を含む（\x00）
    # printf を使用してヌル文字を含む文字列を生成
    malicious_title="$(printf 'Fix\x00bug')"
    
    result="$(run_hook "on_success" "1121" "pi-1121" "" "" "" "0" "$malicious_title")"
    
    # ヌル文字が除去されていることを確認
    [[ "$result" == *"Fixbug"* ]]
}

@test "Issue #1121: PI_ERROR_MESSAGE with carriage return is sanitized" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_error: 'echo "Error: $PI_ERROR_MESSAGE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # エラーメッセージにCR（\r）を含む
    malicious_error=$'Error\rinjection'
    
    result="$(run_hook "on_error" "1121" "pi-1121" "" "" "$malicious_error" "1" "")"
    
    # CRが除去されていることを確認
    [[ ! "$result" =~ $'\r' ]]
    # 制御文字が除去された後の文字列が含まれる
    [[ "$result" == *"Errorinjection"* ]]
}

@test "Issue #1121: PI_ISSUE_TITLE with multiple control characters is sanitized" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # 複数の制御文字を含む
    malicious_title="$(printf 'Fix\nbug\twith\rspecial\x00chars')"
    
    result="$(run_hook "on_success" "1121" "pi-1121" "" "" "" "0" "$malicious_title")"
    
    # 全ての制御文字が除去されていることを確認
    [[ ! "$result" =~ $'\n' ]]
    [[ ! "$result" =~ $'\t' ]]
    [[ ! "$result" =~ $'\r' ]]
    # 制御文字が除去された後の文字列が含まれる
    [[ "$result" == *"Fixbugwithspecialchars"* ]]
}

@test "Issue #1121: PI_ISSUE_TITLE preserves normal spaces" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'echo "Title: $PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # 通常のスペースを含むタイトル
    normal_title="Fix bug in module system"
    
    result="$(run_hook "on_success" "1121" "pi-1121" "" "" "" "0" "$normal_title")"
    
    # スペースが保持されていることを確認
    [[ "$result" == *"Fix bug in module system"* ]]
}

@test "Issue #1121: PI_ERROR_MESSAGE preserves normal text" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_error: 'echo "Error: $PI_ERROR_MESSAGE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # 通常のエラーメッセージ
    normal_error="Command failed with exit code 1"
    
    result="$(run_hook "on_error" "1121" "pi-1121" "" "" "$normal_error" "1" "")"
    
    # 通常のテキストが保持されていることを確認
    [[ "$result" == *"Command failed with exit code 1"* ]]
}

@test "Issue #1121: Other environment variables are not sanitized" {
    mkdir -p "$TEST_WORKDIR/hooks"
    cat > "$TEST_WORKDIR/hooks/test-env.sh" << 'EOF'
#!/bin/bash
echo "NUM:$PI_ISSUE_NUMBER"
echo "SESSION:$PI_SESSION_NAME"
echo "BRANCH:$PI_BRANCH_NAME"
EOF
    chmod +x "$TEST_WORKDIR/hooks/test-env.sh"
    
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << EOF
hooks:
  on_success: $TEST_WORKDIR/hooks/test-env.sh
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # 他の環境変数（サニタイズ不要）
    result="$(run_hook "on_success" "1121" "pi-1121" "feature/issue-1121" "" "" "0" "")"
    
    # 値がそのまま渡されることを確認
    [[ "$result" == *"NUM:1121"* ]]
    [[ "$result" == *"SESSION:pi-1121"* ]]
    [[ "$result" == *"BRANCH:feature/issue-1121"* ]]
}

@test "Issue #1121: Sanitization prevents bash-c command injection" {
    cat > "$TEST_WORKDIR/.pi-runner.yaml" << 'EOF'
hooks:
  on_success: 'printf "Title: %s\n" "$PI_ISSUE_TITLE"'
EOF
    
    source "$PROJECT_ROOT/lib/hooks.sh"
    override_get_config
    mock_notify
    
    # セミコロンと改行を含む悪意のあるタイトル
    malicious_title="$(printf 'Fix bug;\nrm -rf /\necho "done"')"
    
    result="$(run_hook "on_success" "1121" "pi-1121" "" "" "" "0" "$malicious_title")"
    
    # 改行が除去されているため、コマンドは実行されない
    [[ ! "$result" =~ "done" ]] || [[ "$result" == *"Fix bug;rm -rf /echo \"done\""* ]]
}
