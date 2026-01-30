#!/usr/bin/env bats
# run.sh のテスト

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "run.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "run.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/run.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "run.sh fails without issue number" {
    run "$PROJECT_ROOT/scripts/run.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Issue number is required"* ]]
}

@test "run.sh shows usage on unknown option" {
    run "$PROJECT_ROOT/scripts/run.sh" --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "run.sh help contains --branch option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--branch"* ]]
}

@test "run.sh help contains --no-attach option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--no-attach"* ]]
}

@test "run.sh help contains --pi-args option" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"--pi-args"* ]]
}

@test "run.sh help contains examples" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [[ "$output" == *"Examples:"* ]]
}
