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
