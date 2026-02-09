#!/usr/bin/env bats
# test/lib/cleanup-improve-logs.bats - Tests for cleanup-improve-logs.sh

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用ディレクトリを設定
    export TEST_DIR="$BATS_TEST_TMPDIR/test-project"
    export TEST_LOGS_DIR="$TEST_DIR/.improve-logs"
    mkdir -p "$TEST_DIR"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/cleanup-improve-logs.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            improve_logs_keep_recent) echo "${CONFIG_IMPROVE_LOGS_KEEP_RECENT:-10}" ;;
            improve_logs_keep_days) echo "${CONFIG_IMPROVE_LOGS_KEEP_DAYS:-7}" ;;
            improve_logs_dir) echo "${CONFIG_IMPROVE_LOGS_DIR:-.improve-logs}" ;;
            *) echo "" ;;
        esac
    }
    
    # load_config をオーバーライド（環境変数を適用するため呼び出し可能に）
    load_config() {
        if [[ -n "${PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT:-}" ]]; then
            CONFIG_IMPROVE_LOGS_KEEP_RECENT="$PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT"
        fi
        if [[ -n "${PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS:-}" ]]; then
            CONFIG_IMPROVE_LOGS_KEEP_DAYS="$PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS"
        fi
        if [[ -n "${PI_RUNNER_IMPROVE_LOGS_DIR:-}" ]]; then
            CONFIG_IMPROVE_LOGS_DIR="$PI_RUNNER_IMPROVE_LOGS_DIR"
        fi
    }
    
    # reload_config をオーバーライド
    reload_config() {
        load_config
    }
    
    # ログレベルをINFOに設定（テストで出力をキャプチャするため）
    LOG_LEVEL="INFO"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

@test "cleanup_improve_logs: no directory - returns success" {
    cd "$TEST_DIR"
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    # log_debug doesn't output by default, so just check status
}

@test "cleanup_improve_logs: empty directory - no files to delete" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"No improve-logs found"* ]]
}

@test "cleanup_improve_logs: keeps recent N files (default=10)" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    # Create 15 log files
    for i in $(seq 1 15); do
        local filename="iteration-1-$(printf '2026020%01d-120000' $i).log"
        echo "test log $i" > "$TEST_DIR/.improve-logs/$filename"
    done
    
    # Configure to keep only 10 files (default)
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=10
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/.improve-logs"
    reload_config
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    
    # Should keep 10, delete 5
    local remaining=$(find "$TEST_DIR/.improve-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 10 ]
}

@test "cleanup_improve_logs: dry-run mode" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    # Create log files
    for i in $(seq 1 15); do
        echo "test" > "$TEST_DIR/.improve-logs/iteration-1-$(printf '2026020%01d-120000' $i).log"
    done
    
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=5
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/.improve-logs"
    reload_config
    
    run cleanup_improve_logs "true" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
    [[ "$output" == *"Would delete 10 log file(s)"* ]]
    
    # All files should still exist
    local remaining=$(find "$TEST_DIR/.improve-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 15 ]
}

@test "cleanup_improve_logs: age-based cleanup with parameter" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    # Create old file (simulated by timestamp in filename)
    local old_file="$TEST_DIR/.improve-logs/iteration-1-20260125-120000.log"
    echo "old" > "$old_file"
    # Set modification time to 10 days ago
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -t "$(date -v-10d +%Y%m%d%H%M.%S)" "$old_file" 2>/dev/null || true
    else
        touch -t "$(date -d '10 days ago' +%Y%m%d%H%M.%S)" "$old_file" 2>/dev/null || true
    fi
    
    # Create recent file (today)
    local new_file="$TEST_DIR/.improve-logs/iteration-2-20260203-120000.log"
    echo "new" > "$new_file"
    
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=0  # Disable recent count limit
    export PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS=0    # Will be overridden by parameter
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/.improve-logs"
    reload_config
    
    # Pass age_days=7 as parameter (overrides config)
    run cleanup_improve_logs "false" "7"
    [ "$status" -eq 0 ]
    
    # Old file (10 days) should be deleted, new file kept
    [ ! -f "$old_file" ]
    [ -f "$new_file" ]
}

@test "cleanup_improve_logs: keep_recent=0 disables count limit" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    # Create 15 log files
    for i in $(seq 1 15); do
        echo "test" > "$TEST_DIR/.improve-logs/iteration-1-$(printf '2026020%01d-120000' $i).log"
    done
    
    # Configure to keep all (0 = disabled)
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=0
    export PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS=0
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/.improve-logs"
    reload_config
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleanup disabled"* ]]
    
    # All files should remain
    local remaining=$(find "$TEST_DIR/.improve-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 15 ]
}

@test "cleanup_improve_logs: combined recent + days criteria" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    # Create 15 files
    for i in $(seq 1 15); do
        file="$TEST_DIR/.improve-logs/iteration-1-$(printf '2026020%01d-120000' $i).log"
        echo "test $i" > "$file"
        
        # Make files 11-15 old (10 days ago)
        if [[ $i -gt 10 ]]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                touch -t "$(date -v-10d +%Y%m%d%H%M.%S)" "$file" 2>/dev/null || true
            else
                touch -t "$(date -d '10 days ago' +%Y%m%d%H%M.%S)" "$file" 2>/dev/null || true
            fi
        fi
    done
    
    # Keep recent 12 files and 7 days
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=12
    export PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS=7
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/.improve-logs"
    reload_config
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    
    # Files are sorted by modification time (newest first)
    # Files 1-10 are recent (kept)
    # Files 11-15 are old (>7 days), all deleted due to age
    # Result: 10 files remaining
    remaining=$(find "$TEST_DIR/.improve-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 10 ]
}

@test "cleanup_improve_logs: custom log directory from config" {
    mkdir -p "$TEST_DIR/custom-logs"
    cd "$TEST_DIR"
    
    # Create log files in custom directory
    for i in $(seq 1 10); do
        echo "test" > "$TEST_DIR/custom-logs/iteration-1-$(printf '2026020%01d-120000' $i).log"
    done
    
    # Configure custom directory
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=5
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/custom-logs"
    reload_config
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    
    # Should keep 5, delete 5
    local remaining=$(find "$TEST_DIR/custom-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 5 ]
}

@test "_find_improve_log_files: returns files sorted by mtime descending" {
    mkdir -p "$TEST_DIR/.improve-logs"
    
    # Create files with different mtimes
    echo "old" > "$TEST_DIR/.improve-logs/iteration-1-20260201-120000.log"
    sleep 1
    echo "new" > "$TEST_DIR/.improve-logs/iteration-2-20260202-120000.log"
    
    run _find_improve_log_files "$TEST_DIR/.improve-logs"
    [ "$status" -eq 0 ]
    
    # Newest file should be first
    local first_line
    first_line=$(echo "$output" | head -1)
    [[ "$first_line" == *"iteration-2"* ]]
}

@test "_find_improve_log_files: returns empty for no matching files" {
    mkdir -p "$TEST_DIR/.improve-logs"
    echo "not a log" > "$TEST_DIR/.improve-logs/README.md"
    
    run _find_improve_log_files "$TEST_DIR/.improve-logs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_should_cleanup_file: returns reason when exceeds keep_recent" {
    local tmpfile="$BATS_TEST_TMPDIR/iteration-1-20260201-120000.log"
    echo "test" > "$tmpfile"
    
    run _should_cleanup_file "$tmpfile" 6 5 0 ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"exceeds keep_recent limit"* ]]
}

@test "_should_cleanup_file: returns empty when within keep_recent" {
    local tmpfile="$BATS_TEST_TMPDIR/iteration-1-20260201-120000.log"
    echo "test" > "$tmpfile"
    
    run _should_cleanup_file "$tmpfile" 3 5 0 ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_should_cleanup_file: returns reason for old files" {
    local tmpfile="$BATS_TEST_TMPDIR/iteration-1-20260201-120000.log"
    echo "test" > "$tmpfile"
    
    # Set mtime to 10 days ago
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -t "$(date -v-10d +%Y%m%d%H%M.%S)" "$tmpfile"
    else
        touch -t "$(date -d '10 days ago' +%Y%m%d%H%M.%S)" "$tmpfile"
    fi
    
    # Cutoff = 7 days ago
    local cutoff
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cutoff=$(date -v-7d +%s)
    else
        cutoff=$(date -d '7 days ago' +%s)
    fi
    
    run _should_cleanup_file "$tmpfile" 1 0 7 "$cutoff"
    [ "$status" -eq 0 ]
    [[ "$output" == *"older than 7 days"* ]]
}

@test "_remove_improve_log: dry-run does not delete" {
    local tmpfile="$BATS_TEST_TMPDIR/iteration-1-20260201-120000.log"
    echo "test" > "$tmpfile"
    
    run _remove_improve_log "$tmpfile" "test reason" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
    [ -f "$tmpfile" ]
}

@test "_remove_improve_log: actually deletes file" {
    local tmpfile="$BATS_TEST_TMPDIR/iteration-1-20260201-120000.log"
    echo "test" > "$tmpfile"
    
    run _remove_improve_log "$tmpfile" "test reason" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deleting:"* ]]
    [ ! -f "$tmpfile" ]
}

@test "cleanup_improve_logs: ignores non-matching files" {
    mkdir -p "$TEST_DIR/.improve-logs"
    cd "$TEST_DIR"
    
    # Create valid log files
    echo "test" > "$TEST_DIR/.improve-logs/iteration-1-20260203-120000.log"
    echo "test" > "$TEST_DIR/.improve-logs/iteration-2-20260203-120001.log"
    
    # Create files that should be ignored
    echo "test" > "$TEST_DIR/.improve-logs/README.md"
    echo "test" > "$TEST_DIR/.improve-logs/other-log.txt"
    
    export PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT=1
    export PI_RUNNER_IMPROVE_LOGS_DIR="$TEST_DIR/.improve-logs"
    reload_config
    
    run cleanup_improve_logs "false" ""
    [ "$status" -eq 0 ]
    
    # Should keep 1 valid log, delete 1 valid log, ignore 2 non-matching files
    local logs=$(find "$TEST_DIR/.improve-logs" -name "iteration-*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$logs" -eq 1 ]
    
    # Non-matching files should still exist
    [ -f "$TEST_DIR/.improve-logs/README.md" ]
    [ -f "$TEST_DIR/.improve-logs/other-log.txt" ]
}
