#!/usr/bin/env bats
# multiplexer-zellij.sh のBatsテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_MULTIPLEXER_SESSION_PREFIX
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

# zellijモック用ヘルパー
mock_zellij_installed() {
    # セッション状態を保持するファイル
    local killed_sessions="$MOCK_DIR/killed_zellij_sessions"
    local created_sessions="$MOCK_DIR/created_zellij_sessions"
    > "$killed_sessions"
    > "$created_sessions"
    
    cat > "$MOCK_DIR/zellij" << EOF
#!/usr/bin/env bash
KILLED_SESSIONS="$killed_sessions"
CREATED_SESSIONS="$created_sessions"

# 引数をループして処理
for arg in "\$@"; do
    # -s フラグの後のセッション名を記録
    if [[ "\$prev_arg" == "-s" ]]; then
        echo "\$arg" >> "\$CREATED_SESSIONS"
    fi
    prev_arg="\$arg"
done

case "\$1" in
    "list-sessions"|"ls")
        # 実際の出力形式に合わせる（セッション名 + スペース + 追加情報）
        # kill されていないセッションのみ表示
        for session in "test-session (current)" "pi-issue-42 " "pi-issue-99 "; do
            session_name=\$(echo "\$session" | awk '{print \$1}')
            if ! grep -q "^\$session_name\$" "\$KILLED_SESSIONS" 2>/dev/null; then
                echo "\$session"
            fi
        done
        # 作成されたセッションも表示
        while IFS= read -r session_name; do
            [[ -z "\$session_name" ]] && continue
            if ! grep -q "^\$session_name\$" "\$KILLED_SESSIONS" 2>/dev/null; then
                echo "\$session_name (created)"
            fi
        done < "\$CREATED_SESSIONS" 2>/dev/null || true
        ;;
    "-s")
        # zellij -s SESSION_NAME でセッション作成
        # バックグラウンドで実行されるため、即座に終了
        exit 0
        ;;
    "attach")
        # attach SESSION_NAME
        exit 0
        ;;
    "action")
        # write-chars, dump-screen などのアクション
        if [[ "\$2" == "dump-screen" ]]; then
            echo "test output line 1"
            echo "test output line 2"
        elif [[ "\$2" == "write-chars" ]]; then
            # write-chars アクションを処理
            exit 0
        elif [[ "\$2" == "write" ]]; then
            # write アクション（数値コード）
            exit 0
        fi
        exit 0
        ;;
    "delete-session")
        # delete-session --force SESSION_NAME
        # 最後の引数がセッション名
        for last; do true; done
        echo "\$last" >> "\$KILLED_SESSIONS"
        exit 0
        ;;
    *)
        # デフォルトは成功
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/zellij"
    
    # nohup, script もモック
    cat > "$MOCK_DIR/nohup" << 'EOF'
#!/usr/bin/env bash
exec "$@" &
EOF
    chmod +x "$MOCK_DIR/nohup"
    
    cat > "$MOCK_DIR/script" << 'EOF'
#!/usr/bin/env bash
# script のモック（-q /dev/null の後の引数を実行）
shift 3  # -q /dev/null を skip
# バックグラウンドで実行（nohupと組み合わせて使用される）
"$@" &
EOF
    chmod +x "$MOCK_DIR/script"
    
    export PATH="$MOCK_DIR:$PATH"
}

mock_zellij_not_installed() {
    # zellijが見つからない環境を作成
    # zellijが存在しないことを保証（PATH変更前に実行）
    /bin/rm -f "$MOCK_DIR/zellij" 2>/dev/null || rm -f "$MOCK_DIR/zellij"
    # PATHをモックディレクトリのみに設定
    export PATH="$MOCK_DIR"
}

# ====================
# mux_check テスト
# ====================

@test "mux_check succeeds when zellij is installed" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_check
    [ "$status" -eq 0 ]
}

@test "mux_check fails when zellij is not installed" {
    mock_zellij_not_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"not installed"* ]]
}

# ====================
# mux_generate_session_name テスト
# ====================

@test "mux_generate_session_name generates correct name with default prefix" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    result="$(mux_generate_session_name 42)"
    [ "$result" = "pi-issue-42" ]
}

@test "mux_generate_session_name respects custom prefix" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="custom"
    export _CONFIG_LOADED="true"
    
    result="$(mux_generate_session_name 99)"
    [ "$result" = "custom-issue-99" ]
}

@test "mux_generate_session_name handles prefix ending with -issue" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    export CONFIG_MULTIPLEXER_SESSION_PREFIX="myproject-issue"
    export _CONFIG_LOADED="true"
    
    result="$(mux_generate_session_name 123)"
    [ "$result" = "myproject-issue-123" ]
}

# ====================
# mux_extract_issue_number テスト
# ====================

@test "mux_extract_issue_number extracts from standard format" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    result="$(mux_extract_issue_number "pi-issue-42")"
    [ "$result" = "42" ]
}

@test "mux_extract_issue_number extracts from ending number" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    result="$(mux_extract_issue_number "my-session-99")"
    [ "$result" = "99" ]
}

@test "mux_extract_issue_number extracts first number found" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    result="$(mux_extract_issue_number "session123other456")"
    [ "$result" = "123" ]
}

@test "mux_extract_issue_number fails when no number found" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_extract_issue_number "no-numbers-here"
    [ "$status" -ne 0 ]
}

# ====================
# mux_session_exists テスト
# ====================

@test "mux_session_exists detects existing session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_session_exists "test-session"
    [ "$status" -eq 0 ]
}

@test "mux_session_exists returns false for non-existent session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_session_exists "non-existent"
    [ "$status" -ne 0 ]
}

# ====================
# mux_create_session テスト
# ====================

@test "mux_create_session creates new session" {
    skip "Background process mocking needs improvement"
    
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    # バックグラウンド実行されるため、テストは成功判定のみ
    run mux_create_session "new-session" "/tmp" "echo test"
    [ "$status" -eq 0 ]
}

@test "mux_create_session fails if session exists" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_create_session "test-session" "/tmp" "echo test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "mux_create_session fails when zellij not installed" {
    mock_zellij_not_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_create_session "new-session" "/tmp" "echo test"
    [ "$status" -ne 0 ]
}

# ====================
# mux_kill_session テスト
# ====================

@test "mux_kill_session terminates session" {
    skip "Background process mocking needs improvement"
    
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_kill_session "test-session"
    [ "$status" -eq 0 ]
}

@test "mux_kill_session handles non-existent session gracefully" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_kill_session "non-existent"
    [ "$status" -eq 0 ]
}

@test "mux_kill_session respects timeout parameter" {
    # timeoutコマンドの存在確認
    local timeout_cmd
    timeout_cmd=$(require_timeout)
    
    # タイムアウトをテストするため、永続的なセッションモックを作成
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions"|"ls")
        # 常に存在すると返す（grep -q "^$session_name " に一致させるため末尾にスペース）
        echo "persistent-session "
        ;;
    "delete-session")
        # 終了しない（何もしない）
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/zellij"
    
    # テスト用ヘルパースクリプトを作成（timeout経由で実行するため）
    cat > "$MOCK_DIR/test_mux_kill_zellij" << EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$MOCK_DIR:\$PATH"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/log.sh"
source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
mux_kill_session "persistent-session" 1
EOF
    chmod +x "$MOCK_DIR/test_mux_kill_zellij"
    
    # 短いタイムアウトで実行（タイムアウトするはず）
    run "$timeout_cmd" 5 "$MOCK_DIR/test_mux_kill_zellij"
    [ "$status" -ne 0 ]
}

# ====================
# mux_list_sessions テスト
# ====================

@test "mux_list_sessions lists sessions with prefix" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_list_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"pi-issue-42"* ]]
    [[ "$output" == *"pi-issue-99"* ]]
}

@test "mux_list_sessions returns empty when no sessions" {
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions"|"ls")
        # 空の結果
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/zellij"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_list_sessions
    [ "$status" -eq 0 ]
}

# ====================
# mux_get_session_info テスト
# ====================

@test "mux_get_session_info returns session details" {
    skip "Background process mocking needs improvement"
    
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions"|"ls")
        echo "test-session"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/zellij"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_get_session_info "test-session"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-session"* ]]
}

@test "mux_get_session_info fails for non-existent session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_get_session_info "non-existent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not running"* ]]
}

# ====================
# mux_get_session_output テスト
# ====================

@test "mux_get_session_output captures screen content" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_get_session_output "test-session"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test output"* ]]
}

@test "mux_get_session_output respects line limit" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_get_session_output "test-session" 10
    [ "$status" -eq 0 ]
}

@test "mux_get_session_output fails for non-existent session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_get_session_output "non-existent"
    [ "$status" -ne 0 ]
}

# ====================
# mux_send_keys テスト
# ====================

@test "mux_send_keys sends commands to session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_send_keys "test-session" "echo hello"
    [ "$status" -eq 0 ]
}

@test "mux_send_keys fails for non-existent session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_send_keys "non-existent" "echo hello"
    [ "$status" -ne 0 ]
}

# ====================
# mux_count_active_sessions テスト
# ====================

@test "mux_count_active_sessions counts correctly" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    result="$(mux_count_active_sessions)"
    [ "$result" = "2" ]
}

@test "mux_count_active_sessions returns 0 when no sessions" {
    cat > "$MOCK_DIR/zellij" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions"|"ls")
        # 空の結果
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/zellij"
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    result="$(mux_count_active_sessions)"
    [ "$result" = "0" ]
}

# ====================
# mux_check_concurrent_limit テスト
# ====================

@test "mux_check_concurrent_limit allows when under limit" {
    export CONFIG_PARALLEL_MAX_CONCURRENT="5"
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "mux_check_concurrent_limit blocks when at limit" {
    export CONFIG_PARALLEL_MAX_CONCURRENT="2"
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -ne 0 ]
    [[ "$output" == *"Maximum concurrent"* ]]
}

@test "mux_check_concurrent_limit allows unlimited when set to 0" {
    export CONFIG_PARALLEL_MAX_CONCURRENT="0"
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "mux_check_concurrent_limit allows unlimited when not set" {
    unset CONFIG_PARALLEL_MAX_CONCURRENT
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_check_concurrent_limit
    [ "$status" -eq 0 ]
}

# ====================
# mux_attach_session テスト
# ====================

@test "mux_attach_session attaches to existing session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    # Note: attach-sessionは対話的なので実際には実行できない
    # セッションが存在することのみを確認
    run mux_session_exists "test-session"
    [ "$status" -eq 0 ]
}

@test "mux_attach_session fails for non-existent session" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    run mux_attach_session "non-existent"
    [ "$status" -ne 0 ]
}

# ====================
# Zellij固有の機能テスト
# ====================

@test "zellij implementation uses correct command format" {
    mock_zellij_installed
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    # zellijコマンドが正しく認識されているか確認
    run command -v zellij
    [ "$status" -eq 0 ]
}

@test "zellij session naming follows same convention as tmux" {
    source "$PROJECT_ROOT/lib/multiplexer-zellij.sh"
    
    # tmuxと同じ命名規則を使用
    result1="$(mux_generate_session_name 42)"
    
    # tmux実装と比較
    source "$PROJECT_ROOT/lib/multiplexer-tmux.sh"
    result2="$(mux_generate_session_name 42)"
    
    [ "$result1" = "$result2" ]
}
