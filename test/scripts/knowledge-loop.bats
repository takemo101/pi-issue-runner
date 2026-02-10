#!/usr/bin/env bats

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi

    export TEST_PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT"

    git -C "$TEST_PROJECT" init -b main >/dev/null 2>&1
    git -C "$TEST_PROJECT" config user.email "test@example.com"
    git -C "$TEST_PROJECT" config user.name "Test User"

    printf '# Test\n' > "$TEST_PROJECT/README.md"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "initial commit" >/dev/null 2>&1
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# --help
# ====================

@test "knowledge-loop.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--since"* ]]
    [[ "$output" == *"--apply"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "knowledge-loop.sh -h shows usage" {
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ====================
# Unknown option
# ====================

@test "knowledge-loop.sh rejects unknown option" {
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --unknown
    [ "$status" -eq 1 ]
}

# ====================
# Default (dry-run)
# ====================

@test "knowledge-loop.sh default mode shows analysis header" {
    cd "$TEST_PROJECT"
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Knowledge Loop Analysis"* ]]
}

@test "knowledge-loop.sh shows no constraints when none found" {
    cd "$TEST_PROJECT"
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No new constraints found"* ]]
}

@test "knowledge-loop.sh finds fix commits" {
    cd "$TEST_PROJECT"
    printf 'fix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: handle edge case in parser" >/dev/null 2>&1

    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --since "1 week ago"
    [ "$status" -eq 0 ]
    [[ "$output" == *"handle edge case in parser"* ]]
}

# ====================
# --apply
# ====================

@test "knowledge-loop.sh --apply fails when no AGENTS.md" {
    cd "$TEST_PROJECT"
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --apply
    [ "$status" -eq 2 ]
}

@test "knowledge-loop.sh --apply writes to AGENTS.md" {
    cd "$TEST_PROJECT"
    cat > "$TEST_PROJECT/AGENTS.md" << 'EOF'
## 既知の制約

## 注意事項
EOF

    printf 'fix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: use portable date format" >/dev/null 2>&1

    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"Applying proposals"* ]]

    local content
    content="$(cat "$TEST_PROJECT/AGENTS.md")"
    [[ "$content" == *"use portable date format"* ]]
}

# ====================
# --json
# ====================

@test "knowledge-loop.sh --json outputs valid JSON" {
    cd "$TEST_PROJECT"
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null 2>&1
}

@test "knowledge-loop.sh --json outputs empty array when no constraints" {
    cd "$TEST_PROJECT"
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --json
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" = "0" ]
}

@test "knowledge-loop.sh --json includes fix commits" {
    cd "$TEST_PROJECT"
    printf 'fix\n' > "$TEST_PROJECT/file.sh"
    git -C "$TEST_PROJECT" add -A
    git -C "$TEST_PROJECT" commit -m "fix: improve error handling" >/dev/null 2>&1

    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --json --since "1 week ago"
    [ "$status" -eq 0 ]
    local count
    count="$(echo "$output" | jq 'length')"
    [ "$count" -ge 1 ]
    local type
    type="$(echo "$output" | jq -r '.[0].type')"
    [ "$type" = "fix_commit" ]
}

# ====================
# --since
# ====================

@test "knowledge-loop.sh --since respects time range" {
    cd "$TEST_PROJECT"
    run "$PROJECT_ROOT/scripts/knowledge-loop.sh" --since "1 day ago"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Knowledge Loop Analysis"* ]]
}
