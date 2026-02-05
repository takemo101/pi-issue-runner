#!/usr/bin/env bats
# multiplexer-tmux.sh のBatsテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_SESSION_PREFIX
    unset CONFIG_PARALLEL_MAX_CONCURRENT
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # 依存ライブラリをロード
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    source "$PROJECT_ROOT/lib/log.sh"
}

teardown() {
    # PATHを復元
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# tmuxモック用ヘルパー
mock_tmux_installed() {
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        if [[ "$2" == "-t" && "$3" == "test-session" ]]; then
            exit 0
        else
            exit 1
        fi
        ;;
    "new-session")
        echo "tmux new-session called" >&2
        exit 0
        ;;
    "kill-session")
        exit 0
        ;;
    "list-sessions")
        if [[ "$2" == "-F" ]]; then
            echo "pi-issue-42"
            echo "pi-issue-99"
        fi
        ;;
    "list-panes")
        echo "12345"
        ;;
    "capture-pane")
        echo "test output line 1"
        echo "test output line 2"
        ;;
    "send-keys")
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
}

mock_tmux_not_installed() {
    # tmuxコマンドをPATHから削除
    rm -f "$MOCK_DIR/tmux"
}

# ====================
# mux_check テスト
# ====================

@test "mux_check succeeds when tmux is installed" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_check
    [ "$status" -eq 0 ]
}

@test "mux_check fails when tmux is not installed" {
    mock_tmux_not_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_check
    [ "$status" -ne 0 ]
}

# ====================
# mux_generate_session_name テスト
# ====================

@test "mux_generate_session_name generates correct name with default prefix" {
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_generate_session_name 42)"
    [ "$result" = "pi-issue-42" ]
}

@test "mux_generate_session_name respects custom prefix" {
    export CONFIG_SESSION_PREFIX="custom"
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_generate_session_name 99)"
    [ "$result" = "custom-issue-99" ]
}

@test "mux_generate_session_name handles prefix ending with -issue" {
    export CONFIG_SESSION_PREFIX="myproject-issue"
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_generate_session_name 123)"
    [ "$result" = "myproject-issue-123" ]
}

# ====================
# mux_extract_issue_number テスト
# ====================

@test "mux_extract_issue_number extracts from standard format" {
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_extract_issue_number "pi-issue-42")"
    [ "$result" = "42" ]
}

@test "mux_extract_issue_number extracts from ending number" {
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_extract_issue_number "my-session-99")"
    [ "$result" = "99" ]
}

@test "mux_extract_issue_number extracts first number found" {
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_extract_issue_number "session123other456")"
    [ "$result" = "123" ]
}

@test "mux_extract_issue_number fails when no number found" {
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_extract_issue_number "no-numbers-here"
    [ "$status" -ne 0 ]
}

# ====================
# mux_session_exists テスト
# ====================

@test "mux_session_exists detects existing session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_session_exists "test-session"
    [ "$status" -eq 0 ]
}

@test "mux_session_exists returns false for non-existent session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_session_exists "non-existent"
    [ "$status" -ne 0 ]
}

# ====================
# mux_create_session テスト
# ====================

@test "mux_create_session creates new session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_create_session "new-session" "/tmp" "echo test"
    [ "$status" -eq 0 ]
}

@test "mux_create_session fails if session exists" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_create_session "test-session" "/tmp" "echo test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "mux_create_session fails when tmux not installed" {
    mock_tmux_not_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_create_session "new-session" "/tmp" "echo test"
    [ "$status" -ne 0 ]
}

# ====================
# mux_kill_session テスト
# ====================

@test "mux_kill_session terminates session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_kill_session "test-session"
    [ "$status" -eq 0 ]
}

@test "mux_kill_session handles non-existent session gracefully" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_kill_session "non-existent"
    [ "$status" -eq 0 ]
}

@test "mux_kill_session respects timeout parameter" {
    # タイムアウトをテストするため、永続的なセッションモックを作成
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        # 常に存在すると返す
        exit 0
        ;;
    "kill-session")
        # 終了しない
        exit 0
        ;;
    "list-panes")
        echo "99999"  # 存在しないPID
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    # 短いタイムアウトで実行
    run timeout 5 mux_kill_session "persistent-session" 1
    [ "$status" -ne 0 ]
}

# ====================
# mux_list_sessions テスト
# ====================

@test "mux_list_sessions lists sessions with prefix" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_list_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"pi-issue-42"* ]]
    [[ "$output" == *"pi-issue-99"* ]]
}

@test "mux_list_sessions returns empty when no sessions" {
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_list_sessions
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ====================
# mux_get_session_info テスト
# ====================

@test "mux_get_session_info returns session details" {
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0
        ;;
    "list-sessions")
        echo "Name: test-session, Created: 2024-01-01, Windows: 1"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_get_session_info "test-session"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Name: test-session"* ]]
}

@test "mux_get_session_info fails for non-existent session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_get_session_info "non-existent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not running"* ]]
}

# ====================
# mux_get_session_output テスト
# ====================

@test "mux_get_session_output captures pane content" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_get_session_output "test-session"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test output"* ]]
}

@test "mux_get_session_output respects line limit" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_get_session_output "test-session" 10
    [ "$status" -eq 0 ]
}

@test "mux_get_session_output fails for non-existent session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_get_session_output "non-existent"
    [ "$status" -ne 0 ]
}

# ====================
# mux_send_keys テスト
# ====================

@test "mux_send_keys sends commands to session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_send_keys "test-session" "echo hello"
    [ "$status" -eq 0 ]
}

@test "mux_send_keys fails for non-existent session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_send_keys "non-existent" "echo hello"
    [ "$status" -ne 0 ]
}

# ====================
# mux_count_active_sessions テスト
# ====================

@test "mux_count_active_sessions counts correctly" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_count_active_sessions)"
    [ "$result" = "2" ]
}

@test "mux_count_active_sessions returns 0 when no sessions" {
    cat > "$MOCK_DIR/tmux" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    result="$(mux_count_active_sessions)"
    [ "$result" = "0" ]
}

# ====================
# mux_check_concurrent_limit テスト
# ====================

@test "mux_check_concurrent_limit allows when under limit" {
    export CONFIG_PARALLEL_MAX_CONCURRENT="5"
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "mux_check_concurrent_limit blocks when at limit" {
    export CONFIG_PARALLEL_MAX_CONCURRENT="2"
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -ne 0 ]
    [[ "$output" == *"Maximum concurrent"* ]]
}

@test "mux_check_concurrent_limit allows unlimited when set to 0" {
    export CONFIG_PARALLEL_MAX_CONCURRENT="0"
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "mux_check_concurrent_limit allows unlimited when not set" {
    unset CONFIG_PARALLEL_MAX_CONCURRENT
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -eq 0 ]
}

# ====================
# mux_attach_session テスト
# ====================

@test "mux_attach_session attaches to existing session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    # Note: attach-sessionは対話的なので実際には実行できない
    # コマンド構文チェックのみ
    run bash -c "command -v tmux && mux_session_exists test-session"
    [ "$status" -eq 0 ]
}

@test "mux_attach_session fails for non-existent session" {
    mock_tmux_installed
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    
    run mux_attach_session "non-existent"
    [ "$status" -ne 0 ]
}
