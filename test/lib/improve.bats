#!/usr/bin/env bats
# lib/improve.sh のBatsテスト

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
# ライブラリ読み込みテスト
# ====================

@test "improve.sh library can be sourced" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "improve.sh library has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/improve.sh"
    [ "$status" -eq 0 ]
}

@test "improve.sh library sources required dependencies" {
    grep -q "config.sh" "$PROJECT_ROOT/lib/improve.sh"
    grep -q "log.sh" "$PROJECT_ROOT/lib/improve.sh"
    grep -q "github.sh" "$PROJECT_ROOT/lib/improve.sh"
}

# ====================
# 定数定義テスト
# ====================

@test "improve.sh library defines DEFAULT_MAX_ITERATIONS" {
    grep -q 'DEFAULT_MAX_ITERATIONS=' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library defines DEFAULT_MAX_ISSUES" {
    grep -q 'DEFAULT_MAX_ISSUES=' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library defines DEFAULT_TIMEOUT" {
    grep -q 'DEFAULT_TIMEOUT=' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library defines ACTIVE_ISSUE_NUMBERS array" {
    grep -q 'ACTIVE_ISSUE_NUMBERS' "$PROJECT_ROOT/lib/improve.sh"
}

# ====================
# 関数定義テスト
# ====================

@test "improve.sh library has cleanup_on_exit function" {
    grep -q 'cleanup_on_exit()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has usage function" {
    grep -q 'usage()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has parse_improve_arguments function" {
    grep -q 'parse_improve_arguments()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has setup_improve_environment function" {
    grep -q 'setup_improve_environment()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has run_review_phase function" {
    grep -q 'run_review_phase()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has fetch_created_issues function" {
    grep -q 'fetch_created_issues()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has execute_issues_in_parallel function" {
    grep -q 'execute_issues_in_parallel()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has wait_for_completion function" {
    grep -q 'wait_for_completion()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has start_next_iteration function" {
    grep -q 'start_next_iteration()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has check_dependencies function" {
    grep -q 'check_dependencies()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve.sh library has improve_main function" {
    grep -q 'improve_main()' "$PROJECT_ROOT/lib/improve.sh"
}

# ====================
# usage() 関数テスト
# ====================

@test "usage function displays help text" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && usage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "usage function shows all options" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && usage"
    [[ "$output" == *"--max-iterations"* ]]
    [[ "$output" == *"--max-issues"* ]]
    [[ "$output" == *"--timeout"* ]]
    [[ "$output" == *"--log-dir"* ]]
    [[ "$output" == *"--label"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--review-only"* ]]
    [[ "$output" == *"--auto-continue"* ]]
}

@test "usage function shows description" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && usage"
    [[ "$output" == *"Description:"* ]]
}

@test "usage function shows examples" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && usage"
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# parse_improve_arguments() 関数テスト
# ====================

@test "parse_improve_arguments handles --max-iterations" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --max-iterations 5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=5"* ]]
}

@test "parse_improve_arguments handles --max-issues" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --max-issues 10"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_issues=10"* ]]
}

@test "parse_improve_arguments handles --timeout" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --timeout 1800"
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout=1800"* ]]
}

@test "parse_improve_arguments handles --iteration" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --iteration 2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"iteration=2"* ]]
}

@test "parse_improve_arguments handles --log-dir" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --log-dir /tmp/logs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"log_dir='/tmp/logs'"* ]]
}

@test "parse_improve_arguments handles --label" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --label test-session"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_label='test-session'"* ]]
}

@test "parse_improve_arguments handles --dry-run" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --dry-run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry_run=true"* ]]
}

@test "parse_improve_arguments handles --review-only" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --review-only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"review_only=true"* ]]
}

@test "parse_improve_arguments handles --auto-continue" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --auto-continue"
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto_continue=true"* ]]
}

@test "parse_improve_arguments handles --verbose" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --verbose && echo LOG_LEVEL=\$LOG_LEVEL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG_LEVEL=DEBUG"* ]]
}

@test "parse_improve_arguments uses default values" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments"
    [ "$status" -eq 0 ]
    [[ "$output" == *"max_iterations=3"* ]]
    [[ "$output" == *"max_issues=5"* ]]
    [[ "$output" == *"timeout=3600"* ]]
    [[ "$output" == *"iteration=1"* ]]
}

# ====================
# check_dependencies() 関数テスト
# ====================

@test "check_dependencies function exists" {
    grep -q 'check_dependencies()' "$PROJECT_ROOT/lib/improve.sh"
}

@test "check_dependencies checks for pi command" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'pi_command'* ]]
}

@test "check_dependencies checks for gh command" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'command -v gh'* ]]
}

@test "check_dependencies checks for jq command" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'command -v jq'* ]]
}

# ====================
# ワークフローフェーズテスト
# ====================

@test "improve.sh library implements 5 phases" {
    grep -q 'PHASE 1' "$PROJECT_ROOT/lib/improve.sh"
    grep -q 'PHASE 2' "$PROJECT_ROOT/lib/improve.sh"
    grep -q 'PHASE 3' "$PROJECT_ROOT/lib/improve.sh"
    grep -q 'PHASE 4' "$PROJECT_ROOT/lib/improve.sh"
    grep -q 'PHASE 5' "$PROJECT_ROOT/lib/improve.sh"
}

@test "run_review_phase uses pi --print" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'--print'* ]]
}

@test "fetch_created_issues uses get_issues_created_after" {
    grep -q 'get_issues_created_after' "$PROJECT_ROOT/lib/improve.sh"
}

@test "execute_issues_in_parallel uses run.sh --no-attach" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'run.sh'* ]]
    [[ "$source_content" == *'--no-attach'* ]]
}

@test "wait_for_completion uses wait-for-sessions.sh" {
    grep -q 'wait-for-sessions.sh' "$PROJECT_ROOT/lib/improve.sh"
}

@test "start_next_iteration uses exec for recursion" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'exec "$0"'* ]]
}

# ====================
# cleanup_on_exit() 関数テスト
# ====================

@test "cleanup_on_exit function handles active sessions" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'ACTIVE_ISSUE_NUMBERS'* ]]
    [[ "$source_content" == *'cleanup.sh'* ]]
}

@test "cleanup_on_exit uses --force flag" {
    grep -q 'cleanup.sh.*--force' "$PROJECT_ROOT/lib/improve.sh"
}

# ====================
# improve_main() 関数テスト
# ====================

@test "improve_main sets up trap" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'trap cleanup_on_exit'* ]]
}

@test "improve_main calls all workflow phases" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    # Check for phase function calls
    [[ "$source_content" == *'parse_improve_arguments'* ]]
    [[ "$source_content" == *'setup_improve_environment'* ]]
    [[ "$source_content" == *'run_review_phase'* ]]
    [[ "$source_content" == *'fetch_created_issues'* ]]
    [[ "$source_content" == *'execute_issues_in_parallel'* ]]
    [[ "$source_content" == *'wait_for_completion'* ]]
    [[ "$source_content" == *'start_next_iteration'* ]]
}

# ====================
# セッションラベル機能テスト
# ====================

@test "setup_improve_environment generates session label" {
    grep -q 'generate_session_label' "$PROJECT_ROOT/lib/improve.sh"
}

@test "setup_improve_environment creates GitHub label" {
    grep -q 'create_label_if_not_exists' "$PROJECT_ROOT/lib/improve.sh"
}

@test "setup_improve_environment skips label creation in dry-run mode" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'dry_run" != "true"'* ]]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "run_review_phase handles pi command failure" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'pi command returned non-zero'* ]]
}

@test "fetch_created_issues handles no issues gracefully" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'No new Issues created'* ]]
}

@test "execute_issues_in_parallel handles session start failure" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'Failed to start session'* ]]
}

# ====================
# --dry-run / --review-only モードテスト
# ====================

@test "run_review_phase supports dry-run mode" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'Dry-run mode complete'* ]]
    [[ "$source_content" == *'No Issues were created'* ]]
}

@test "run_review_phase supports review-only mode" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'Review-only mode complete'* ]]
}

@test "dry-run mode exits early" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    [[ "$source_content" == *'Issueは作成しないでください'* ]]
}

# ====================
# 行数テスト
# ====================

@test "lib/improve.sh is reasonably sized" {
    line_count=$(wc -l < "$PROJECT_ROOT/lib/improve.sh")
    # Should be less than 550 lines (current is ~499)
    [ "$line_count" -lt 550 ]
}

@test "lib/improve.sh is larger than minimal size" {
    line_count=$(wc -l < "$PROJECT_ROOT/lib/improve.sh")
    # Should be more than 400 lines (current is ~499)
    [ "$line_count" -gt 400 ]
}
