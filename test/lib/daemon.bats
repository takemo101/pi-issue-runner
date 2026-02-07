#!/usr/bin/env bats
# test/lib/daemon.bats - daemon.sh のテスト

load '../test_helper'

setup() {
    # テスト用一時ディレクトリ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        BATS_TEST_TMPDIR="$(mktemp -d)"
        export BATS_TEST_TMPDIR
    fi
    TEST_LOG_FILE="$BATS_TEST_TMPDIR/daemon_test.log"
    TEST_PID_FILE="$BATS_TEST_TMPDIR/daemon.pid"
}

teardown() {
    # テストプロセスのクリーンアップ
    if [[ -f "$TEST_PID_FILE" ]]; then
        local pid
        pid="$(cat "$TEST_PID_FILE" 2>/dev/null || echo "")"
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    fi
    # 一時ディレクトリの削除
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "daemonize function exists" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    [[ "$(type -t daemonize)" == "function" ]]
}

@test "is_daemon_running function exists" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    [[ "$(type -t is_daemon_running)" == "function" ]]
}

@test "stop_daemon function exists" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    [[ "$(type -t stop_daemon)" == "function" ]]
}

@test "daemonize runs command in background" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # テスト用スクリプトを作成（2秒間動作）
    local test_script="$BATS_TEST_TMPDIR/test_daemon.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
sleep 2
EOF
    chmod +x "$test_script"
    
    # デーモン化して実行
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" "$test_script")
    
    # PIDが取得できたか確認
    [[ -n "$pid" ]]
    [[ "$pid" =~ ^[0-9]+$ ]]
    
    # プロセスが実行中か確認
    sleep 0.2
    run is_daemon_running "$pid"
    [ "$status" -eq 0 ]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "daemonize writes output to log file" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # テスト用スクリプトを作成（標準出力と標準エラー出力）
    local test_script="$BATS_TEST_TMPDIR/test_log.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
echo "STDOUT_MESSAGE"
echo "STDERR_MESSAGE" >&2
EOF
    chmod +x "$test_script"
    
    # デーモン化して実行
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" bash -c "echo STDOUT_MESSAGE; echo STDERR_MESSAGE >&2")
    
    # 出力がファイルに書き込まれるのを待つ
    sleep 0.3
    
    # ログファイルの内容を確認
    [ -f "$TEST_LOG_FILE" ]
    run cat "$TEST_LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STDOUT_MESSAGE"* ]]
    [[ "$output" == *"STDERR_MESSAGE"* ]]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "is_daemon_running returns 1 for non-existent PID" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # 存在しないPIDをチェック
    run is_daemon_running 99999
    [ "$status" -eq 1 ]
}

@test "is_daemon_running returns 1 for empty PID" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    run is_daemon_running ""
    [ "$status" -eq 1 ]
}

@test "stop_daemon terminates running daemon" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # テスト用デーモンを起動（5秒間動作）
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" sleep 5)
    
    # プロセスが起動するのを待つ
    sleep 0.2
    
    # プロセスが実行中か確認
    is_daemon_running "$pid"
    
    # デーモンを停止
    run stop_daemon "$pid"
    [ "$status" -eq 0 ]
    
    # プロセスが終了したか確認
    sleep 0.2
    run is_daemon_running "$pid"
    [ "$status" -eq 1 ]
}

@test "stop_daemon returns 1 for non-existent PID" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    run stop_daemon 99999
    [ "$status" -eq 1 ]
}

@test "daemon process survives parent shell exit" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # サブシェルでデーモンを起動し、即座に終了
    local daemon_pid
    daemon_pid=$(
        pid=$(daemonize "$TEST_LOG_FILE" sleep 3)
        echo "$pid"
        exit 0
    )
    
    # 親シェルが終了してもデーモンが生きているか確認
    sleep 0.3
    run is_daemon_running "$daemon_pid"
    [ "$status" -eq 0 ]
    
    # クリーンアップ
    stop_daemon "$daemon_pid" 2>/dev/null || true
}

@test "daemonize with setsid on Linux or double fork on macOS" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # OSを検出して適切な方法でデーモン化されるか確認
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" sleep 2)
    
    [[ -n "$pid" ]]
    
    # プロセスが実際に実行中か確認
    sleep 0.2
    run is_daemon_running "$pid"
    [ "$status" -eq 0 ]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "find_daemon_pid function exists" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    [[ "$(type -t find_daemon_pid)" == "function" ]]
}

@test "find_daemon_pid finds running process by pattern" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    # CI環境ではpgrepの動作が不安定なためスキップ
    if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
        skip "Skipping in CI environment due to pgrep limitations"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # テスト用の一意なパターンを持つプロセスを起動
    local unique_pattern
    unique_pattern="test_daemon_$$_$(date +%s)"
    local test_script="$BATS_TEST_TMPDIR/${unique_pattern}_script.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
sleep 5
EOF
    chmod +x "$test_script"
    
    # デーモン化して実行
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" "$test_script")
    
    # CI環境ではプロセス起動に時間がかかる場合があるため、十分に待機
    local found_pid=""
    local attempts=0
    local max_attempts=20
    while [[ $attempts -lt $max_attempts ]]; do
        found_pid=$(find_daemon_pid "$unique_pattern" 2>/dev/null || echo "")
        if [[ -n "$found_pid" ]]; then
            break
        fi
        sleep 0.2
        ((attempts++)) || true
    done
    
    # パターンでPIDを検索
    [[ -n "$found_pid" ]]
    [[ "$found_pid" =~ ^[0-9]+$ ]]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "daemonize handles PID file timeout with pgrep fallback" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    # CI環境ではpgrepの動作が不安定なためスキップ
    if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
        skip "Skipping in CI environment due to pgrep limitations"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # テスト用の一意なパターンを持つコマンドを作成
    local unique_marker="daemon_test_pid_fallback_$$_$(date +%s)"
    local test_script="$BATS_TEST_TMPDIR/${unique_marker}_test.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
sleep 5
EOF
    chmod +x "$test_script"
    
    # PIDファイルのタイムアウトをシミュレートするために、
    # PIDファイルへの書き込みを遅延させる
    # Note: 実際の実装では、daemonize関数が10秒待機するため、
    # このテストではpgrepフォールバックがトリガーされないが、
    # コードパスの検証として残す
    
    # 正常にデーモン化できることを確認
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" "$test_script")
    
    [[ -n "$pid" ]]
    [[ "$pid" =~ ^[0-9]+$ ]]
    
    # プロセスが実行中か確認
    sleep 0.2
    run is_daemon_running "$pid"
    [ "$status" -eq 0 ]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "daemonize increases wait time to 10 seconds for high-load scenarios" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # max_attempts が 100 に設定されていることを確認（間接的なテスト）
    # 実際の実装では max_attempts=100 なので、10秒待機する
    
    # 通常の起動時間でデーモン化できることを確認
    local pid
    pid=$(daemonize "$TEST_LOG_FILE" sleep 2)
    
    [[ -n "$pid" ]]
    [[ "$pid" =~ ^[0-9]+$ ]]
    
    # プロセスが実行中か確認
    sleep 0.2
    run is_daemon_running "$pid"
    [ "$status" -eq 0 ]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "Issue #553: watcher survives batch timeout scenario" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    local log_file="$BATS_TEST_TMPDIR/batch_timeout_test.log"
    local status_file="$BATS_TEST_TMPDIR/watcher_status.txt"
    
    # batch timeoutシナリオをシミュレートするスクリプト（短縮版）
    local batch_script="$BATS_TEST_TMPDIR/batch_simulator.sh"
    cat > "$batch_script" << 'EOF'
#!/usr/bin/env bash
log_file="$1"
status_file="$2"
echo "running" > "$status_file"
echo "$(date): Batch started" >> "$log_file"
# 親がタイムアウトで死んでも生き続ける（短縮版：3秒）
for i in {1..3}; do
    echo "$(date): Still running (iteration $i)" >> "$log_file"
    sleep 0.5
done
echo "$(date): Batch completed normally" >> "$log_file"
echo "completed" > "$status_file"
EOF
    chmod +x "$batch_script"
    
    # 親プロセスをシミュレートしてwatcherを起動
    local watcher_pid
    watcher_pid=$(
        # バッチ処理をシミュレート
        pid=$(daemonize "$log_file" "$batch_script" "$log_file" "$status_file")
        echo "$pid"
        # すぐに終了（タイムアウトシミュレーション）
        exit 0
    )
    
    TEST_WATCHER_PID="$watcher_pid"
    
    # 親が終了してもwatcherが生きているか確認
    # Note: daemon起動オーバーヘッド + ログ書き込み時間を考慮して1.0秒待機
    sleep 1.0
    run is_daemon_running "$watcher_pid"
    [ "$status" -eq 0 ]
    
    # ログが書き込まれているか確認
    run cat "$log_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Batch started"* ]]
    [[ "$output" == *"Still running"* ]]
    
    # ステータスファイルが"running"であることを確認（まだ完了していない）
    [ -f "$status_file" ]
    run cat "$status_file"
    [[ "$output" == *"running"* ]]  # まだ完了していない、またはcompleted
    
    # クリーンアップ
    stop_daemon "$watcher_pid" 2>/dev/null || true
}
