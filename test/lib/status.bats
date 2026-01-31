#!/usr/bin/env bats
# status.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_WORKTREE_BASE_DIR
    
    # テスト用の設定ファイルを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/test-config.yaml"
    cat > "$TEST_CONFIG_FILE" << 'EOF'
worktree:
  base_dir: "${BATS_TEST_TMPDIR}/.worktrees"
EOF
    
    # worktree_base_dirを一時ディレクトリに設定
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# json_escape テスト
# ====================

@test "json_escape escapes double quotes" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    result="$(json_escape 'Hello "World"')"
    [ "$result" = 'Hello \"World\"' ]
}

@test "json_escape escapes backslashes" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    result="$(json_escape 'Path: C:\Users')"
    [ "$result" = 'Path: C:\\Users' ]
}

@test "json_escape escapes newlines" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    result="$(json_escape $'Line1\nLine2')"
    [ "$result" = 'Line1\nLine2' ]
}

@test "json_escape handles multiple special chars" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    result="$(json_escape $'Quote: " Tab:\t')"
    [[ "$result" == *'\"'* ]]
    [[ "$result" == *'\t'* ]]
}

# ====================
# get_status_dir テスト
# ====================

@test "get_status_dir returns correct path" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    result="$(get_status_dir)"
    [[ "$result" == *".worktrees/.status" ]]
}

# ====================
# init_status_dir テスト
# ====================

@test "init_status_dir creates directory" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    init_status_dir
    status_dir="$(get_status_dir)"
    [ -d "$status_dir" ]
}

# ====================
# save_status / load_status テスト
# ====================

@test "save_status creates status file" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "running" "pi-issue-42"
    
    status_dir="$(get_status_dir)"
    [ -f "$status_dir/42.json" ]
}

@test "save_status writes correct JSON" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "running" "pi-issue-42"
    
    status_dir="$(get_status_dir)"
    json="$(cat "$status_dir/42.json")"
    
    [[ "$json" == *'"issue": 42'* ]]
    [[ "$json" == *'"status": "running"'* ]]
    [[ "$json" == *'"session": "pi-issue-42"'* ]]
}

@test "save_status with error message" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "43" "error" "pi-issue-43" "Test error"
    
    status_dir="$(get_status_dir)"
    json="$(cat "$status_dir/43.json")"
    
    [[ "$json" == *'"status": "error"'* ]]
    [[ "$json" == *'"error_message"'* ]]
    [[ "$json" == *'Test error'* ]]
}

@test "load_status returns JSON content" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "complete" "pi-issue-42"
    json="$(load_status "42")"
    
    [[ "$json" == *'"issue": 42'* ]]
}

@test "load_status returns empty for non-existent" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    init_status_dir
    result="$(load_status "999")"
    [ -z "$result" ]
}

# ====================
# get_status_value / get_status テスト
# ====================

@test "get_status_value returns status string" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "running" "pi-issue-42"
    result="$(get_status_value "42")"
    [ "$result" = "running" ]
}

@test "get_status_value returns unknown for missing" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    init_status_dir
    result="$(get_status_value "999")"
    [ "$result" = "unknown" ]
}

@test "get_status is alias for get_status_value" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "complete" "pi-issue-42"
    result="$(get_status "42")"
    [ "$result" = "complete" ]
}

# ====================
# set_status テスト
# ====================

@test "set_status creates status with generated session name" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    set_status "50" "running"
    result="$(get_status "50")"
    [ "$result" = "running" ]
}

@test "set_status with error message" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    set_status "51" "error" "Something went wrong"
    
    result="$(get_status "51")"
    [ "$result" = "error" ]
    
    error_msg="$(get_error_message "51")"
    [ "$error_msg" = "Something went wrong" ]
}

# ====================
# get_error_message テスト
# ====================

@test "get_error_message returns error message" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "error" "pi-issue-42" "Error occurred"
    result="$(get_error_message "42")"
    [ "$result" = "Error occurred" ]
}

@test "get_error_message returns empty for non-error status" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "running" "pi-issue-42"
    result="$(get_error_message "42")"
    [ -z "$result" ]
}

# ====================
# remove_status テスト
# ====================

@test "remove_status deletes status file" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "42" "running" "pi-issue-42"
    remove_status "42"
    
    result="$(get_status_value "42")"
    [ "$result" = "unknown" ]
}

# ====================
# list_all_statuses テスト
# ====================

@test "list_all_statuses returns all statuses" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "10" "running" "pi-issue-10"
    save_status "20" "complete" "pi-issue-20"
    
    result="$(list_all_statuses)"
    
    [[ "$result" == *"10"* ]]
    [[ "$result" == *"running"* ]]
    [[ "$result" == *"20"* ]]
    [[ "$result" == *"complete"* ]]
}

@test "list_all_statuses returns empty for no statuses" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    init_status_dir
    result="$(list_all_statuses)"
    [ -z "$result" ]
}

# ====================
# list_issues_by_status テスト
# ====================

@test "list_issues_by_status filters by status" {
    source "$PROJECT_ROOT/lib/status.sh"
    
    save_status "10" "running" "pi-issue-10"
    save_status "20" "running" "pi-issue-20"
    save_status "30" "complete" "pi-issue-30"
    
    result="$(list_issues_by_status "running")"
    
    [[ "$result" == *"10"* ]]
    [[ "$result" == *"20"* ]]
    [[ "$result" != *"30"* ]]
}
