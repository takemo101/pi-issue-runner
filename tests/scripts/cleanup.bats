#!/usr/bin/env bats
# cleanup.sh のテスト

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "cleanup.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cleanup.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cleanup.sh fails without target" {
    run "$PROJECT_ROOT/scripts/cleanup.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "cleanup.sh help contains --force option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--force"* ]]
}

@test "cleanup.sh help contains --keep-session option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--keep-session"* ]]
}

@test "cleanup.sh help contains --keep-worktree option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--keep-worktree"* ]]
}

@test "cleanup.sh help contains examples" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"Examples:"* ]]
}
