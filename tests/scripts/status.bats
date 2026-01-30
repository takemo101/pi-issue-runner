#!/usr/bin/env bats
# status.sh のテスト

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "status.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/status.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "status.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/status.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "status.sh runs without arguments" {
    # status.shは引数なしでも動作する
    run "$PROJECT_ROOT/scripts/status.sh"
    [ "$status" -eq 0 ]
}

@test "status.sh help contains --all option" {
    run "$PROJECT_ROOT/scripts/status.sh" --help
    [[ "$output" == *"--all"* ]]
}

@test "status.sh help contains --json option" {
    run "$PROJECT_ROOT/scripts/status.sh" --help
    [[ "$output" == *"--json"* ]]
}
