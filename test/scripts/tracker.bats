#!/usr/bin/env bats

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    export TRACKER_FILE="$TEST_WORKTREE_DIR/.status/tracker.jsonl"
    mkdir -p "$TEST_WORKTREE_DIR/.status"

    cat > "$BATS_TEST_TMPDIR/.pi-runner.yaml" << EOF
worktree:
  base_dir: $TEST_WORKTREE_DIR
EOF
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

_create_test_entries() {
    cat > "$TRACKER_FILE" << 'EOF'
{"issue":100,"workflow":"default","result":"success","duration_sec":120,"timestamp":"2026-02-10T08:00:00Z"}
{"issue":101,"workflow":"default","result":"success","duration_sec":180,"timestamp":"2026-02-10T09:00:00Z"}
{"issue":102,"workflow":"default","result":"error","duration_sec":300,"error_type":"test_failure","timestamp":"2026-02-10T10:00:00Z"}
{"issue":103,"workflow":"fix","result":"success","duration_sec":60,"timestamp":"2026-02-10T11:00:00Z"}
{"issue":104,"workflow":"fix","result":"success","duration_sec":90,"timestamp":"2026-02-10T12:00:00Z"}
{"issue":105,"workflow":"feature","result":"error","duration_sec":420,"error_type":"merge_conflict","timestamp":"2026-02-10T13:00:00Z"}
{"issue":106,"workflow":"feature","result":"success","duration_sec":360,"timestamp":"2026-02-10T14:00:00Z"}
EOF
}

# ====================
# --help
# ====================

@test "tracker.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/tracker.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ====================
# No entries
# ====================

@test "tracker.sh shows no entries when file missing" {
    run "$PROJECT_ROOT/scripts/tracker.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No entries found"* ]]
}

@test "tracker.sh --json outputs empty array when no file" {
    run "$PROJECT_ROOT/scripts/tracker.sh" --json
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# ====================
# Summary (default)
# ====================

@test "tracker.sh shows summary" {
    _create_test_entries
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Prompt Tracker Summary"* ]]
    [[ "$output" == *"7 tasks"* ]]
    [[ "$output" == *"5 success"* ]]
    [[ "$output" == *"2 error"* ]]
}

# ====================
# --by-workflow
# ====================

@test "tracker.sh --by-workflow shows workflow breakdown" {
    _create_test_entries
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --by-workflow
    [ "$status" -eq 0 ]
    [[ "$output" == *"By Workflow:"* ]]
    [[ "$output" == *"default"* ]]
    [[ "$output" == *"fix"* ]]
    [[ "$output" == *"feature"* ]]
}

# ====================
# --failures
# ====================

@test "tracker.sh --failures shows failure list" {
    _create_test_entries
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --failures
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recent Failures:"* ]]
    [[ "$output" == *"test_failure"* ]]
    [[ "$output" == *"merge_conflict"* ]]
}

@test "tracker.sh --failures shows nothing when all succeed" {
    cat > "$TRACKER_FILE" << 'EOF'
{"issue":100,"workflow":"default","result":"success","duration_sec":120,"timestamp":"2026-02-10T08:00:00Z"}
EOF
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --failures
    [ "$status" -eq 0 ]
    [[ "$output" == *"No failures found"* ]]
}

# ====================
# --json
# ====================

@test "tracker.sh --json outputs valid JSON array" {
    _create_test_entries
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null 2>&1
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" = "7" ]
}

# ====================
# Unknown option
# ====================

# ====================
# --gates
# ====================

@test "tracker.sh --gates shows gate statistics" {
    cat > "$TRACKER_FILE" << 'EOF'
{"issue":100,"workflow":"default","result":"success","duration_sec":120,"gates":{"shellcheck":{"result":"pass","attempts":1},"bats":{"result":"pass","attempts":2}},"total_gate_retries":1,"timestamp":"2026-02-10T08:00:00Z"}
{"issue":101,"workflow":"default","result":"success","duration_sec":180,"gates":{"shellcheck":{"result":"pass","attempts":1},"bats":{"result":"pass","attempts":1}},"total_gate_retries":0,"timestamp":"2026-02-10T09:00:00Z"}
{"issue":102,"workflow":"fix","result":"error","duration_sec":300,"gates":{"shellcheck":{"result":"fail","attempts":3}},"total_gate_retries":2,"timestamp":"2026-02-10T10:00:00Z"}
EOF
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --gates
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gate Statistics"* ]]
    [[ "$output" == *"shellcheck"* ]]
    [[ "$output" == *"bats"* ]]
}

@test "tracker.sh --gates shows no gate data message" {
    _create_test_entries
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --gates
    [ "$status" -eq 0 ]
    [[ "$output" == *"No gate data found"* ]]
}

@test "tracker.sh --gates shows total retries" {
    cat > "$TRACKER_FILE" << 'EOF'
{"issue":100,"workflow":"default","result":"success","duration_sec":120,"gates":{"shellcheck":{"result":"pass","attempts":1}},"total_gate_retries":2,"timestamp":"2026-02-10T08:00:00Z"}
{"issue":101,"workflow":"default","result":"success","duration_sec":180,"gates":{"shellcheck":{"result":"pass","attempts":1}},"total_gate_retries":3,"timestamp":"2026-02-10T09:00:00Z"}
EOF
    export PI_RUNNER_TRACKER_FILE="$TRACKER_FILE"
    run "$PROJECT_ROOT/scripts/tracker.sh" --gates
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total retries across all entries: 5"* ]]
}

# ====================
# Unknown option
# ====================

@test "tracker.sh rejects unknown option" {
    run "$PROJECT_ROOT/scripts/tracker.sh" --unknown
    [ "$status" -eq 1 ]
}
