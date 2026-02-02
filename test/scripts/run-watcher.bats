#!/usr/bin/env bats
# test/scripts/run-watcher.bats - run.shのwatcher起動機能のテスト

load '../test_helper'

setup() {
    # テスト用一時ディレクトリ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        BATS_TEST_TMPDIR="$(mktemp -d)"
        export BATS_TEST_TMPDIR
    fi
    
    # 必要なライブラリを読み込み
    source "$PROJECT_ROOT/lib/daemon.sh"
}

teardown() {
    # テストプロセスのクリーンアップ
    if [[ -n "${TEST_WATCHER_PID:-}" ]]; then
        stop_daemon "$TEST_WATCHER_PID" 2>/dev/null || true
    fi
    
    # 一時ディレクトリの削除
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "daemonize function is available in run.sh context" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # daemonize関数が正しく定義されているか確認
    [[ "$(type -t daemonize)" == "function" ]]
    [[ "$(type -t is_daemon_running)" == "function" ]]
}

@test "watcher process survives parent shell termination" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    local log_file="$BATS_TEST_TMPDIR/watcher_survive.log"
    local marker_file="$BATS_TEST_TMPDIR/watcher_started.marker"
    
    # 監視用スクリプトを作成（親が死んでも生き続ける）
    local watcher_script="$BATS_TEST_TMPDIR/survive_test.sh"
    cat > "$watcher_script" << 'EOF'
#!/usr/bin/env bash
# test_watcher_survive
marker_file="$1"
log_file="$2"
echo "$(date): Watcher started" >> "$log_file"
touch "$marker_file"
# 30秒間待機
sleep 30
echo "$(date): Watcher completed" >> "$log_file"
EOF
    chmod +x "$watcher_script"
    
    # サブシェルでデーモンを起動し、即座に終了
    local daemon_pid
    daemon_pid=$(
        pid=$(daemonize "$log_file" "$watcher_script" "$marker_file" "$log_file")
        echo "$pid"
        exit 0
    )
    
    # 親シェルが終了してもデーモンが生きているか確認
    sleep 0.5
    
    # マーカーファイルが作成されたか確認（watcherが起動した証拠）
    [ -f "$marker_file" ]
    
    # デーモンプロセスが実行中か確認
    run is_daemon_running "$daemon_pid"
    [ "$status" -eq 0 ]
    
    # クリーンアップ
    stop_daemon "$daemon_pid" 2>/dev/null || true
}

@test "watcher log file is created and written" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    local log_file="$BATS_TEST_TMPDIR/watcher_log_test.log"
    local unique_pattern
    unique_pattern="log_test_$$_$(date +%s)"
    
    # ログを出力するスクリプト
    local script="$BATS_TEST_TMPDIR/log_writer.sh"
    cat > "$script" << EOF
#!/usr/bin/env bash
# $unique_pattern
echo "START_MARKER"
sleep 5
echo "END_MARKER"
EOF
    chmod +x "$script"
    
    # デーモン化して実行
    local pid
    pid=$(daemonize "$log_file" "$script")
    
    # ログが書き込まれるのを待つ
    sleep 0.3
    
    # ログファイルが存在し、内容が書き込まれているか確認
    [ -f "$log_file" ]
    run cat "$log_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"START_MARKER"* ]]
    
    # クリーンアップ
    stop_daemon "$pid" 2>/dev/null || true
}

@test "Issue #553: watcher survives batch timeout scenario" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    local log_file="$BATS_TEST_TMPDIR/batch_timeout_test.log"
    local status_file="$BATS_TEST_TMPDIR/watcher_status.txt"
    
    # batch timeoutシナリオをシミュレートするスクリプト
    local batch_script="$BATS_TEST_TMPDIR/batch_simulator.sh"
    cat > "$batch_script" << 'EOF'
#!/usr/bin/env bash
log_file="$1"
status_file="$2"
echo "running" > "$status_file"
echo "$(date): Batch started" >> "$log_file"
# 親がタイムアウトで死んでも生き続ける
for i in {1..30}; do
    echo "$(date): Still running (iteration $i)" >> "$log_file"
    sleep 1
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
    sleep 1
    run is_daemon_running "$watcher_pid"
    [ "$status" -eq 0 ]
    
    # ログが書き込まれているか確認
    run cat "$log_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Batch started"* ]]
    [[ "$output" == *"Still running"* ]]
    
    # ステータスファイルが"running"であることを確認
    [ -f "$status_file" ]
    run cat "$status_file"
    [ "$output" == "running" ]  # まだ完了していない
    
    # クリーンアップ
    stop_daemon "$watcher_pid" 2>/dev/null || true
}
