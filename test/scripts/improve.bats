#!/usr/bin/env bats
# improve.sh のBatsテスト (2段階方式)

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
# ヘルプオプションテスト
# ====================

@test "improve.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [ "$status" -eq 0 ]
}

@test "improve.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "improve.sh --help shows --max-iterations option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--max-iterations"* ]]
}

@test "improve.sh --help shows --max-issues option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--max-issues"* ]]
}

@test "improve.sh --help shows --timeout option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--timeout"* ]]
}

@test "improve.sh --help shows --verbose option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--verbose"* ]]
}

@test "improve.sh --help shows --log-dir option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--log-dir"* ]]
}

@test "improve.sh --help shows --dry-run option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--dry-run"* ]]
}

@test "improve.sh --help shows --review-only option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--review-only"* ]]
}

@test "improve.sh --help shows --auto-continue option" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"--auto-continue"* ]]
}

@test "improve.sh --help shows description" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Description:"* ]]
}

@test "improve.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Examples:"* ]]
}

@test "improve.sh --help shows log file information" {
    run "$PROJECT_ROOT/scripts/improve.sh" --help
    [[ "$output" == *"Log files:"* ]]
}

@test "improve.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/improve.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# オプションパーステスト
# ====================

@test "improve.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/improve.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "improve.sh with unexpected argument fails" {
    run "$PROJECT_ROOT/scripts/improve.sh" unexpected-arg
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected argument"* ]]
}

# ====================
# スクリプト構造テスト
# ====================

@test "improve.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/improve.sh"
    [ "$status" -eq 0 ]
}

@test "improve.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh sources github.sh" {
    grep -q "lib/github.sh" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has check_dependencies function" {
    grep -q "check_dependencies()" "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# オプション処理テスト
# ====================

@test "improve.sh handles --max-iterations option" {
    grep -q '\-\-max-iterations)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has max_iterations variable" {
    grep -q 'max_iterations=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --max-issues option" {
    grep -q '\-\-max-issues)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --timeout option" {
    grep -q '\-\-timeout)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --iteration option" {
    grep -q '\-\-iteration)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --log-dir option" {
    grep -q '\-\-log-dir)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --dry-run option" {
    grep -q '\-\-dry-run)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --review-only option" {
    grep -q '\-\-review-only)' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh handles --auto-continue option" {
    grep -q '\-\-auto-continue)' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# デフォルト値テスト
# ====================

@test "improve.sh has DEFAULT_MAX_ITERATIONS" {
    grep -q 'DEFAULT_MAX_ITERATIONS=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has DEFAULT_MAX_ISSUES" {
    grep -q 'DEFAULT_MAX_ISSUES=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has DEFAULT_TIMEOUT" {
    grep -q 'DEFAULT_TIMEOUT=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has LOG_DIR" {
    grep -q 'LOG_DIR=' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# オプションフラグテスト
# ====================

@test "improve.sh has dry_run variable" {
    grep -q 'dry_run=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has review_only variable" {
    grep -q 'review_only=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has auto_continue variable" {
    grep -q 'auto_continue=' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# 依存関係チェックテスト
# ====================

@test "improve.sh checks for pi command" {
    grep -q 'pi_command' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh checks for gh command" {
    grep -q 'command -v gh' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh checks for jq command" {
    grep -q 'command -v jq' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh reports missing dependencies" {
    grep -q 'Missing dependencies' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# 2段階方式ワークフローテスト
# ====================

@test "improve.sh has phase 1 for pi --print review" {
    grep -q 'PHASE 1' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has phase 2 for fetching issues" {
    grep -q 'PHASE 2' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has phase 3 for parallel execution" {
    grep -q 'PHASE 3' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has phase 4 for session monitoring" {
    grep -q 'PHASE 4' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has phase 5 for next iteration" {
    grep -q 'PHASE 5' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh uses project-review skill" {
    grep -q 'project-review' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh uses wait-for-sessions.sh" {
    grep -q 'wait-for-sessions.sh' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh shows iteration counter" {
    grep -q 'Iteration' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has recursive exec call" {
    grep -q 'exec "$0"' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh checks max iterations" {
    grep -q 'max_iterations' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# pi --print テスト
# ====================

@test "improve.sh uses pi --print mode" {
    grep -q -- '--print' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh uses tee for log output" {
    grep -q 'tee' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh creates log directory" {
    grep -q 'mkdir -p "$log_dir"' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh generates log file name with timestamp" {
    grep -q 'iteration-.*$(date' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# GitHub API テスト
# ====================

@test "improve.sh uses get_issues_created_after" {
    grep -q 'get_issues_created_after' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh records start_time for issue filtering" {
    grep -q 'start_time=' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh uses run.sh with --no-attach" {
    grep -q 'run.sh.*--no-attach' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# エラーハンドリングテスト
# ====================

@test "improve.sh handles no issues created gracefully" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'No new Issues created'* ]]
}

@test "improve.sh handles pi command failure" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'pi command returned non-zero'* ]]
}

@test "improve.sh handles session start failure" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'Failed to start session'* ]]
}

# ====================
# クリーンアップ機能テスト (Issue #247)
# ====================

@test "improve.sh has cleanup_on_exit function" {
    grep -q 'cleanup_on_exit()' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh has ACTIVE_ISSUE_NUMBERS array" {
    grep -q 'ACTIVE_ISSUE_NUMBERS' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh sets trap for EXIT INT TERM" {
    grep -q 'trap cleanup_on_exit EXIT INT TERM' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh calls wait-for-sessions.sh with --cleanup option" {
    grep -q 'wait-for-sessions.sh.*--cleanup' "$PROJECT_ROOT/scripts/improve.sh"
}

@test "improve.sh tracks active sessions in array" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'ACTIVE_ISSUE_NUMBERS+=("$issue")'* ]]
}

@test "improve.sh clears active sessions after completion" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'ACTIVE_ISSUE_NUMBERS=()'* ]]
}

@test "improve.sh cleanup uses --force flag" {
    grep -q 'cleanup.sh.*--force' "$PROJECT_ROOT/scripts/improve.sh"
}

# ====================
# --dry-run オプションテスト
# ====================

@test "improve.sh dry-run mode modifies prompt" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'Issueは作成しないでください'* ]]
}

@test "improve.sh dry-run mode exits early" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'Dry-run mode complete'* ]]
}

@test "improve.sh dry-run mode shows message about no Issues created" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'No Issues were created'* ]]
}

# ====================
# --review-only オプションテスト
# ====================

@test "improve.sh review-only mode exits early" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'Review-only mode complete'* ]]
}

# ====================
# --auto-continue オプションテスト
# ====================

@test "improve.sh has confirmation prompt for manual mode" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'Press Enter to continue'* ]]
}

@test "improve.sh preserves --auto-continue flag in recursive call" {
    source_content=$(cat "$PROJECT_ROOT/scripts/improve.sh")
    [[ "$source_content" == *'args+=(--auto-continue)'* ]]
}
