#!/usr/bin/env bats
# status.sh のBatsテスト

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
    source "$PROJECT_ROOT/lib/status.sh"
    
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

# ====================
# set_status テスト（エイリアス）
# ====================

@test "set_status sets running status" {
    set_status "50" "running"
    [ -f "$TEST_WORKTREE_DIR/.status/50.json" ]
    result="$(get_status "50")"
    [ "$result" = "running" ]
}

@test "set_status sets complete status" {
    set_status "51" "complete"
    result="$(get_status "51")"
    [ "$result" = "complete" ]
}

@test "set_status sets error status with message" {
    set_status "52" "error" "Something went wrong"
    result="$(get_status "52")"
    [ "$result" = "error" ]
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
# get_status テスト（エイリアス）
# ====================

@test "get_status returns running" {
    save_status "42" "running" "pi-issue-42"
    result="$(get_status "42")"
    [ "$result" = "running" ]
}

@test "get_status returns unknown for non-existent" {
    result="$(get_status "999")"
    [ "$result" = "unknown" ]
}

# ====================
# get_error_message テスト
# ====================

@test "get_error_message returns error message" {
    save_status "43" "error" "pi-issue-43" "Test error message"
    result="$(get_error_message "43")"
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
# list_all_statuses テスト
# ====================

@test "list_all_statuses includes created issues" {
    save_status "100" "running" "pi-issue-100"
    save_status "101" "complete" "pi-issue-101"
    
    result="$(list_all_statuses)"
    [[ "$result" == *"100"* ]]
    [[ "$result" == *"101"* ]]
}

# ====================
# list_issues_by_status テスト
# ====================

@test "list_issues_by_status returns running issues" {
    save_status "100" "running" "pi-issue-100"
    save_status "101" "complete" "pi-issue-101"
    
    result="$(list_issues_by_status "running")"
    [[ "$result" == *"100"* ]]
}

@test "list_issues_by_status returns complete issues" {
    save_status "100" "running" "pi-issue-100"
    save_status "101" "complete" "pi-issue-101"
    
    result="$(list_issues_by_status "complete")"
    [[ "$result" == *"101"* ]]
}

# ====================
# json_escape テスト
# ====================

@test "json_escape handles backslash" {
    result="$(json_escape 'test\backslash')"
    [ "$result" = 'test\\backslash' ]
}

@test "json_escape handles double quotes" {
    result="$(json_escape 'test"quote')"
    [ "$result" = 'test\"quote' ]
}

@test "json_escape handles tabs" {
    result="$(json_escape $'test\ttab')"
    [ "$result" = 'test\ttab' ]
}

@test "json_escape handles newlines" {
    result="$(json_escape $'line1\nline2')"
    [ "$result" = 'line1\nline2' ]
}

@test "json_escape handles carriage returns" {
    result="$(json_escape $'test\rreturn')"
    [ "$result" = 'test\rreturn' ]
}

# ====================
# 複雑なエラーメッセージテスト
# ====================

@test "save_status with complex error message produces valid JSON" {
    complex_error=$'Error on line 1\nError on line 2 with "quotes"'
    save_status "45" "error" "pi-issue-45" "$complex_error"
    
    if command -v jq &>/dev/null; then
        cat "$TEST_WORKTREE_DIR/.status/45.json" | jq . > /dev/null 2>&1
    else
        skip "jq not installed"
    fi
}

# ====================
# build_status_json テスト（統一関数）
# ====================

@test "build_status_json produces valid JSON with jq" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_status_json "42" "running" "pi-issue-42" "2025-01-01T00:00:00Z")"
    echo "$result" | jq . > /dev/null 2>&1
    [ "$(echo "$result" | jq -r '.issue')" = "42" ]
    [ "$(echo "$result" | jq -r '.status')" = "running" ]
    [ "$(echo "$result" | jq -r '.session')" = "pi-issue-42" ]
}

@test "build_status_json includes error_message when provided" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_status_json "42" "error" "pi-issue-42" "2025-01-01T00:00:00Z" "something broke")"
    [ "$(echo "$result" | jq -r '.error_message')" = "something broke" ]
    [ "$(echo "$result" | jq 'has("session_label")')" = "false" ]
}

@test "build_status_json includes session_label when provided" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_status_json "42" "running" "pi-issue-42" "2025-01-01T00:00:00Z" "" "my-label")"
    [ "$(echo "$result" | jq -r '.session_label')" = "my-label" ]
    [ "$(echo "$result" | jq 'has("error_message")')" = "false" ]
}

@test "build_status_json includes both error_message and session_label" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_status_json "42" "error" "pi-issue-42" "2025-01-01T00:00:00Z" "err msg" "lbl")"
    [ "$(echo "$result" | jq -r '.error_message')" = "err msg" ]
    [ "$(echo "$result" | jq -r '.session_label')" = "lbl" ]
}

@test "build_status_json omits optional fields when empty" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_status_json "42" "running" "pi-issue-42" "2025-01-01T00:00:00Z")"
    [ "$(echo "$result" | jq 'has("error_message")')" = "false" ]
    [ "$(echo "$result" | jq 'has("session_label")')" = "false" ]
}

@test "build_status_json handles special characters in error_message" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_status_json "42" "error" "pi-issue-42" "2025-01-01T00:00:00Z" $'line1\nline2\t"quoted"')"
    echo "$result" | jq . > /dev/null 2>&1
    # jq properly escapes the value; verify round-trip
    decoded="$(echo "$result" | jq -r '.error_message')"
    [[ "$decoded" == *"line1"* ]]
    [[ "$decoded" == *"line2"* ]]
    [[ "$decoded" == *'"quoted"'* ]]
}

@test "build_json_with_jq is backward-compatible alias for build_status_json" {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
    result="$(build_json_with_jq "10" "running" "pi-issue-10" "2025-01-01T00:00:00Z")"
    echo "$result" | jq . > /dev/null 2>&1
    [ "$(echo "$result" | jq -r '.issue')" = "10" ]
}

# ====================
# build_json_fallback テスト
# ====================

@test "build_json_fallback produces valid JSON" {
    if command -v jq &>/dev/null; then
        result="$(build_json_fallback "99" "error" "pi-issue-99" "2025-01-01T00:00:00Z" $'Error\nwith\tnewlines')"
        echo "$result" | jq . > /dev/null 2>&1
    else
        skip "jq not installed"
    fi
}

@test "build_json_fallback without error produces valid JSON" {
    if command -v jq &>/dev/null; then
        result="$(build_json_fallback "98" "running" "pi-issue-98" "2025-01-01T00:00:00Z")"
        echo "$result" | jq . > /dev/null 2>&1
    else
        skip "jq not installed"
    fi
}

# ====================
# find_orphaned_statuses テスト
# ====================

@test "find_orphaned_statuses returns orphaned issues" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # ステータスファイルを作成（対応するworktreeなし）
    save_status "100" "complete" "pi-issue-100"
    save_status "200" "running" "pi-issue-200"
    
    # 対応するworktreeが存在しないので両方とも孤立扱い
    result="$(find_orphaned_statuses)"
    
    [[ "$result" == *"100"* ]]
    [[ "$result" == *"200"* ]]
}

@test "find_orphaned_statuses returns empty for no orphans" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # worktreeディレクトリを作成
    local worktree_base="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "$worktree_base/issue-300-test"
    
    # 対応するステータスファイルを作成
    save_status "300" "running" "pi-issue-300"
    
    # worktreeが存在するので孤立ではない
    result="$(find_orphaned_statuses)"
    
    [[ "$result" != *"300"* ]]
}

@test "find_orphaned_statuses handles mixed cases" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # worktreeディレクトリを作成
    local worktree_base="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "$worktree_base/issue-400-with-worktree"
    
    # 一つは対応するworktreeあり、一つはなし
    save_status "400" "running" "pi-issue-400"  # worktreeあり
    save_status "500" "complete" "pi-issue-500"  # worktreeなし
    
    result="$(find_orphaned_statuses)"
    
    # 500は孤立、400は孤立ではない
    [[ "$result" == *"500"* ]]
    [[ "$result" != *"400"* ]]
}

@test "find_orphaned_statuses returns empty for no status files" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    init_status_dir
    result="$(find_orphaned_statuses)"
    [ -z "$result" ]
}

@test "find_orphaned_statuses does not misdetect worktree without title suffix" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # worktreeディレクトリをタイトルサフィックスなしで作成（例: issue-42）
    local worktree_base="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "$worktree_base/issue-700"
    
    # 対応するステータスファイルを作成
    save_status "700" "running" "pi-issue-700"
    
    # worktreeが存在するので孤立ではない
    result="$(find_orphaned_statuses)"
    [[ "$result" != *"700"* ]]
}

@test "find_orphaned_statuses does not false-match similar issue numbers" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # issue-4 の worktree を作成（issue-42 とは別）
    local worktree_base="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "$worktree_base/issue-4-some-title"
    
    # issue-42 のステータスファイルを作成（対応するworktreeなし）
    save_status "42" "running" "pi-issue-42"
    
    # issue-4 の worktree は issue-42 にマッチしないので、42 は孤立
    result="$(find_orphaned_statuses)"
    [[ "$result" == *"42"* ]]
}

# ====================
# count_orphaned_statuses テスト
# ====================

@test "count_orphaned_statuses returns correct count" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # 孤立したステータスファイルを作成
    save_status "600" "complete" "pi-issue-600"
    save_status "601" "complete" "pi-issue-601"
    save_status "602" "running" "pi-issue-602"
    
    result="$(count_orphaned_statuses)"
    [ "$result" -eq 3 ]
}

@test "count_orphaned_statuses returns 0 for no orphans" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    init_status_dir
    result="$(count_orphaned_statuses)"
    [ "$result" -eq 0 ]
}

@test "count_orphaned_statuses excludes non-orphans" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # worktreeディレクトリを作成
    local worktree_base="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "$worktree_base/issue-700-test"
    
    # 一つは対応するworktreeあり、一つはなし
    save_status "700" "running" "pi-issue-700"  # worktreeあり
    save_status "800" "complete" "pi-issue-800"  # worktreeなし
    
    result="$(count_orphaned_statuses)"
    [ "$result" -eq 1 ]
}

# ====================
# find_old_statuses テスト
# ====================

@test "find_old_statuses returns empty for new files" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # 新しいファイルを作成
    save_status "900" "complete" "pi-issue-900"
    
    # 0日より古いファイルを検索（今日作成したファイルは対象外）
    result="$(find_old_statuses 0)"
    [ -z "$result" ]
}

@test "find_old_statuses finds old files" {
    # このテストはtouch -tが遅いため、デフォルトではスキップ
    if [[ "${BATS_ENABLE_SLOW_TESTS:-}" != "1" ]]; then
        skip "Skipping slow timestamp test (set BATS_ENABLE_SLOW_TESTS=1 to enable)"
    fi
    
    source "$PROJECT_ROOT/lib/status.sh"
    
    # ステータスファイルを作成して日付を過去に変更
    save_status "901" "complete" "pi-issue-901"
    touch -t 202001010000 "$TEST_WORKTREE_DIR/.status/901.json"
    
    # 1日より古いファイルを検索
    result="$(find_old_statuses 1)"
    [[ "$result" == *"901"* ]]
}

# ====================
# find_stale_statuses テスト
# ====================

@test "find_stale_statuses returns orphaned files when no age specified" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # 孤立したステータスファイルを作成
    save_status "950" "complete" "pi-issue-950"
    
    result="$(find_stale_statuses)"
    [[ "$result" == *"950"* ]]
}

@test "find_stale_statuses filters by age when specified" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # 新しい孤立ファイル
    save_status "960" "complete" "pi-issue-960"
    
    # 0日より古いものを検索（新しいファイルは対象外）
    result="$(find_stale_statuses 0)"
    [[ "$result" != *"960"* ]] || [ -z "$result" ]
}

# ====================
# Watcher PID Management テスト (Issue #693)
# ====================

@test "save_watcher_pid creates PID file" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_watcher_pid "693" "12345"
    
    local pid_file="$TEST_WORKTREE_DIR/.status/693.watcher.pid"
    [ -f "$pid_file" ]
    [ "$(cat "$pid_file")" = "12345" ]
}

@test "load_watcher_pid returns saved PID" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_watcher_pid "693" "54321"
    result="$(load_watcher_pid "693")"
    
    [ "$result" = "54321" ]
}

@test "load_watcher_pid returns empty for non-existent PID file" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    result="$(load_watcher_pid "999")"
    [ -z "$result" ]
}

@test "remove_watcher_pid deletes PID file" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_watcher_pid "693" "99999"
    local pid_file="$TEST_WORKTREE_DIR/.status/693.watcher.pid"
    [ -f "$pid_file" ]
    
    remove_watcher_pid "693"
    [ ! -f "$pid_file" ]
}

@test "remove_watcher_pid handles non-existent file gracefully" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Should not fail
    run remove_watcher_pid "999"
    [ "$status" -eq 0 ]
}

@test "is_watcher_running returns false for non-existent PID" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    run is_watcher_running "999"
    [ "$status" -eq 1 ]
}

@test "is_watcher_running checks actual process status" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Save PID of current shell (which is running)
    save_watcher_pid "693" "$$"
    
    run is_watcher_running "693"
    [ "$status" -eq 0 ]
}

@test "is_watcher_running returns false for invalid PID" {
    source "$PROJECT_ROOT/lib/daemon.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Use a PID that doesn't exist
    save_watcher_pid "693" "999999"
    
    run is_watcher_running "693"
    [ "$status" -eq 1 ]
}

# ====================
# Atomic Write Tests (Issue #874)
# ====================

@test "save_status uses atomic write (no temp file remains)" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "874" "running" "pi-issue-874"
    
    # Check that no temporary files remain
    local tmp_files
    tmp_files=$(find "$TEST_WORKTREE_DIR/.status" -name "*.tmp.*" 2>/dev/null || true)
    [ -z "$tmp_files" ]
    
    # Verify the actual file exists
    [ -f "$TEST_WORKTREE_DIR/.status/874.json" ]
}

@test "save_status produces valid JSON after atomic write" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "874" "running" "pi-issue-874"
    
    if command -v jq &>/dev/null; then
        cat "$TEST_WORKTREE_DIR/.status/874.json" | jq . > /dev/null 2>&1
    else
        # Fallback: check for basic JSON structure
        grep -q '"issue": 874' "$TEST_WORKTREE_DIR/.status/874.json"
        grep -q '"status": "running"' "$TEST_WORKTREE_DIR/.status/874.json"
    fi
}

@test "save_watcher_pid uses atomic write (no temp file remains)" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_watcher_pid "874" "12345"
    
    # Check that no temporary files remain
    local tmp_files
    tmp_files=$(find "$TEST_WORKTREE_DIR/.status" -name "*.tmp.*" 2>/dev/null || true)
    [ -z "$tmp_files" ]
    
    # Verify the actual file exists
    [ -f "$TEST_WORKTREE_DIR/.status/874.watcher.pid" ]
}

@test "save_watcher_pid produces valid content after atomic write" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_watcher_pid "874" "54321"
    
    # Verify content
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/874.watcher.pid")
    [ "$pid" = "54321" ]
}

@test "save_status parallel writes produce valid JSON" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Run multiple parallel writes
    for i in $(seq 1 20); do
        (save_status "875" "running" "test-$i") &
    done
    wait
    
    # Verify the final file is valid JSON
    if command -v jq &>/dev/null; then
        cat "$TEST_WORKTREE_DIR/.status/875.json" | jq . > /dev/null 2>&1
    else
        # Fallback: check for basic JSON structure
        grep -q '"issue": 875' "$TEST_WORKTREE_DIR/.status/875.json"
        grep -q '"status":' "$TEST_WORKTREE_DIR/.status/875.json"
    fi
    
    # Verify no temp files remain
    local tmp_files
    tmp_files=$(find "$TEST_WORKTREE_DIR/.status" -name "*.tmp.*" 2>/dev/null || true)
    [ -z "$tmp_files" ]
}

@test "save_watcher_pid parallel writes produce valid content" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Run multiple parallel writes
    for i in $(seq 1 20); do
        (save_watcher_pid "876" "$((10000 + i))") &
    done
    wait
    
    # Verify the final file contains a valid PID
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/876.watcher.pid")
    [[ "$pid" =~ ^[0-9]+$ ]]
    
    # Verify no temp files remain
    local tmp_files
    tmp_files=$(find "$TEST_WORKTREE_DIR/.status" -name "*.tmp.*" 2>/dev/null || true)
    [ -z "$tmp_files" ]
}

# ====================
# Cleanup Lock Tests (Issue #1077)
# ====================

@test "acquire_cleanup_lock creates lock directory" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    acquire_cleanup_lock "1077"
    
    [ -d "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock" ]
    [ -f "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid" ]
}

@test "acquire_cleanup_lock writes current PID" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    acquire_cleanup_lock "1077"
    
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid")
    [ "$pid" = "$$" ]
}

@test "acquire_cleanup_lock fails if lock exists" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # First acquisition succeeds
    acquire_cleanup_lock "1077"
    
    # Create a subprocess to try to acquire the same lock
    run bash -c "
        source '$PROJECT_ROOT/lib/status.sh'
        get_config() {
            case \"\$1\" in
                worktree_base_dir) echo \"$TEST_WORKTREE_DIR\" ;;
                *) echo \"\" ;;
            esac
        }
        acquire_cleanup_lock 1077
    "
    [ "$status" -eq 1 ]
}

@test "acquire_cleanup_lock succeeds after stale lock cleanup" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Create a stale lock with non-existent PID
    mkdir -p "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid"
    
    # Should succeed by removing stale lock
    acquire_cleanup_lock "1077"
    
    # Verify new lock has current PID
    local pid
    pid=$(cat "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid")
    [ "$pid" = "$$" ]
}

@test "acquire_cleanup_lock stale recovery overwrites PID without removing directory (TOCTOU fix)" {
    source "$PROJECT_ROOT/lib/status.sh"

    # Create a stale lock with non-existent PID
    local lock_dir="$TEST_WORKTREE_DIR/.status/1077.cleanup.lock"
    mkdir -p "$lock_dir"
    echo "999999" > "$lock_dir/pid"

    # Get inode of lock directory before acquisition (ls -di is portable across macOS/Linux)
    local inode_before
    inode_before=$(ls -di "$lock_dir" | awk '{print $1}')

    # Should succeed by overwriting PID (not rm+mkdir)
    acquire_cleanup_lock "1077"

    # Verify PID was updated
    local pid
    pid=$(cat "$lock_dir/pid")
    [ "$pid" = "$$" ]

    # Verify directory was NOT recreated (same inode = no rm+mkdir)
    local inode_after
    inode_after=$(ls -di "$lock_dir" | awk '{print $1}')
    [ "$inode_before" = "$inode_after" ]
}

@test "release_cleanup_lock removes lock directory" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    acquire_cleanup_lock "1077"
    [ -d "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock" ]
    
    release_cleanup_lock "1077"
    [ ! -d "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock" ]
}

@test "release_cleanup_lock does not remove other process lock" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Create a lock owned by another process (use parent PID which should be running)
    local other_pid
    other_pid=$PPID
    mkdir -p "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock"
    echo "$other_pid" > "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid"
    
    # Verify the other PID is actually running
    kill -0 "$other_pid" 2>/dev/null || skip "Parent process not accessible for testing"
    
    # Try to release - should not remove
    release_cleanup_lock "1077"
    
    # Lock should still exist
    [ -d "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock" ]
}

@test "release_cleanup_lock removes stale lock" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Create a stale lock with non-existent PID
    mkdir -p "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid"
    
    # Should remove stale lock
    release_cleanup_lock "1077"
    
    [ ! -d "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock" ]
}

@test "is_cleanup_locked returns true when locked" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    acquire_cleanup_lock "1077"
    
    run is_cleanup_locked "1077"
    [ "$status" -eq 0 ]
}

@test "is_cleanup_locked returns false when not locked" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    run is_cleanup_locked "1077"
    [ "$status" -eq 1 ]
}

@test "is_cleanup_locked returns false for stale lock" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Create a stale lock with non-existent PID
    mkdir -p "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock"
    echo "999999" > "$TEST_WORKTREE_DIR/.status/1077.cleanup.lock/pid"
    
    run is_cleanup_locked "1077"
    [ "$status" -eq 1 ]
}

@test "cleanup lock prevents concurrent cleanup" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    # Process 1 acquires lock
    acquire_cleanup_lock "1077"
    
    # Process 2 tries to acquire - should fail
    # Note: Pass TEST_WORKTREE_DIR as an environment variable to the subprocess
    run bash -c "
        TEST_WORKTREE_DIR='$TEST_WORKTREE_DIR'
        source '$PROJECT_ROOT/lib/status.sh'
        get_config() {
            case \"\$1\" in
                worktree_base_dir) echo \"\$TEST_WORKTREE_DIR\" ;;
                *) echo \"\" ;;
            esac
        }
        acquire_cleanup_lock 1077
    "
    [ "$status" -eq 1 ]
    
    # Process 2 checks if locked
    run bash -c "
        TEST_WORKTREE_DIR='$TEST_WORKTREE_DIR'
        source '$PROJECT_ROOT/lib/status.sh'
        get_config() {
            case \"\$1\" in
                worktree_base_dir) echo \"\$TEST_WORKTREE_DIR\" ;;
                *) echo \"\" ;;
            esac
        }
        is_cleanup_locked 1077
    "
    [ "$status" -eq 0 ]
    
    # Process 1 releases
    release_cleanup_lock "1077"
    
    # Process 2 can now acquire
    run bash -c "
        TEST_WORKTREE_DIR='$TEST_WORKTREE_DIR'
        source '$PROJECT_ROOT/lib/status.sh'
        get_config() {
            case \"\$1\" in
                worktree_base_dir) echo \"\$TEST_WORKTREE_DIR\" ;;
                *) echo \"\" ;;
            esac
        }
        acquire_cleanup_lock 1077
    "
    [ "$status" -eq 0 ]
}
