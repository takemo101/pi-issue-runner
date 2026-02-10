#!/usr/bin/env bats

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"

    reset_config_state
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tracker.sh"

    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            tracker_file) echo "" ;;
            *) echo "" ;;
        esac
    }

    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# get_tracker_file
# ====================

@test "get_tracker_file returns default path" {
    result="$(get_tracker_file)"
    [[ "$result" == "$TEST_WORKTREE_DIR/.status/tracker.jsonl" ]]
}

@test "get_tracker_file uses config override" {
    get_config() {
        case "$1" in
            tracker_file) echo "/custom/path/tracker.jsonl" ;;
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    result="$(get_tracker_file)"
    [[ "$result" == "/custom/path/tracker.jsonl" ]]
}

# ====================
# save_tracker_metadata
# ====================

@test "save_tracker_metadata creates meta file" {
    save_tracker_metadata "42" "default"
    [ -f "$TEST_WORKTREE_DIR/.status/42.tracker-meta" ]
}

@test "save_tracker_metadata stores workflow name" {
    save_tracker_metadata "42" "feature"
    local first_line
    first_line="$(head -1 "$TEST_WORKTREE_DIR/.status/42.tracker-meta")"
    [ "$first_line" = "feature" ]
}

@test "save_tracker_metadata stores 3 lines" {
    save_tracker_metadata "42" "default"
    local line_count
    line_count="$(wc -l < "$TEST_WORKTREE_DIR/.status/42.tracker-meta" | tr -d ' ')"
    [ "$line_count" = "3" ]
}

# ====================
# load_tracker_metadata
# ====================

@test "load_tracker_metadata returns tab-separated values" {
    save_tracker_metadata "42" "fix"
    result="$(load_tracker_metadata "42")"
    [[ "$result" == fix$'\t'* ]]
}

@test "load_tracker_metadata fails for missing issue" {
    run load_tracker_metadata "999"
    [ "$status" -eq 1 ]
}

# ====================
# remove_tracker_metadata
# ====================

@test "remove_tracker_metadata deletes meta file" {
    save_tracker_metadata "42" "default"
    [ -f "$TEST_WORKTREE_DIR/.status/42.tracker-meta" ]
    remove_tracker_metadata "42"
    [ ! -f "$TEST_WORKTREE_DIR/.status/42.tracker-meta" ]
}

@test "remove_tracker_metadata is idempotent" {
    remove_tracker_metadata "999"
}

# ====================
# record_tracker_entry
# ====================

@test "record_tracker_entry creates JSONL file" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    [ -f "$TEST_WORKTREE_DIR/.status/tracker.jsonl" ]
}

@test "record_tracker_entry writes valid JSON" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    echo "$line" | jq . >/dev/null 2>&1
}

@test "record_tracker_entry includes issue number" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local issue
    issue="$(echo "$line" | jq '.issue')"
    [ "$issue" = "42" ]
}

@test "record_tracker_entry includes workflow name from metadata" {
    save_tracker_metadata "42" "feature"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local wf
    wf="$(echo "$line" | jq -r '.workflow')"
    [ "$wf" = "feature" ]
}

@test "record_tracker_entry sets result to success" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local result_val
    result_val="$(echo "$line" | jq -r '.result')"
    [ "$result_val" = "success" ]
}

@test "record_tracker_entry sets result to error" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "error" "test_failure"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local result_val
    result_val="$(echo "$line" | jq -r '.result')"
    [ "$result_val" = "error" ]
}

@test "record_tracker_entry includes error_type when provided" {
    save_tracker_metadata "42" "fix"
    record_tracker_entry "42" "error" "merge_conflict"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local et
    et="$(echo "$line" | jq -r '.error_type')"
    [ "$et" = "merge_conflict" ]
}

@test "record_tracker_entry omits error_type on success" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local et
    et="$(echo "$line" | jq -r '.error_type // "none"')"
    [ "$et" = "none" ]
}

@test "record_tracker_entry includes duration_sec" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local dur
    dur="$(echo "$line" | jq '.duration_sec')"
    [[ "$dur" =~ ^[0-9]+$ ]]
}

@test "record_tracker_entry includes timestamp" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local ts
    ts="$(echo "$line" | jq -r '.timestamp')"
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "record_tracker_entry removes metadata after recording" {
    save_tracker_metadata "42" "default"
    [ -f "$TEST_WORKTREE_DIR/.status/42.tracker-meta" ]
    record_tracker_entry "42" "success"
    [ ! -f "$TEST_WORKTREE_DIR/.status/42.tracker-meta" ]
}

@test "record_tracker_entry uses 'unknown' workflow when no metadata" {
    record_tracker_entry "42" "success"
    local line
    line="$(cat "$TEST_WORKTREE_DIR/.status/tracker.jsonl")"
    local wf
    wf="$(echo "$line" | jq -r '.workflow')"
    [ "$wf" = "unknown" ]
}

@test "record_tracker_entry appends multiple entries" {
    save_tracker_metadata "42" "default"
    record_tracker_entry "42" "success"
    save_tracker_metadata "43" "fix"
    record_tracker_entry "43" "error" "test_failure"
    local count
    count="$(wc -l < "$TEST_WORKTREE_DIR/.status/tracker.jsonl" | tr -d ' ')"
    [ "$count" = "2" ]
}
