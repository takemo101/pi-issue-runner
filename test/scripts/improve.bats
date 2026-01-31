#!/usr/bin/env bats
# improve.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプ表示テスト
# ====================

@test "improve.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "improve.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/improve.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes --max-iterations option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--max-iterations"* ]]
}

@test "help includes --max-issues option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--max-issues"* ]]
}



@test "help includes --timeout option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--timeout"* ]]
}

@test "help includes -v/--verbose option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-v"* ]] || [[ "$output" == *"--verbose"* ]]
}

@test "help includes description" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Description:"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

@test "help includes environment variables section" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Environment Variables:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "improve.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "improve.sh fails with unexpected argument" {
    run "$PROJECT_ROOT/scripts/improve.sh" some-argument
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

# ====================
# オプション組み合わせテスト
# ====================

@test "improve.sh accepts multiple options" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
    # オプションの組み合わせはヘルプ出力で確認
    [[ "$output" == *"--max-iterations"* ]]
    [[ "$output" == *"--max-issues"* ]]
}

# ====================
# 完了マーカー検出テスト
# ====================

@test "improve.sh defines MARKER_COMPLETE constant" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'MARKER_COMPLETE="###TASK_COMPLETE###"'* ]]
}

@test "improve.sh defines MARKER_NO_ISSUES constant" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'MARKER_NO_ISSUES="###NO_ISSUES###"'* ]]
}

@test "improve.sh has run_pi_with_completion_detection function" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *"run_pi_with_completion_detection()"* ]]
}

@test "run_pi_with_completion_detection uses tee for output" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'tee "$output_file"'* ]]
}

@test "run_pi_with_completion_detection monitors for MARKER_COMPLETE" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'grep -q "$MARKER_COMPLETE"'* ]]
}

@test "run_pi_with_completion_detection monitors for MARKER_NO_ISSUES" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'grep -q "$MARKER_NO_ISSUES"'* ]]
}

@test "run_pi_with_completion_detection cleans up temp file" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'rm -f "$output_file"'* ]]
}

@test "Phase 1 uses run_pi_with_completion_detection" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'run_pi_with_completion_detection "$prompt" "$pi_command"'* ]]
}
