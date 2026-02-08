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
# モジュール構造テスト
# ====================

@test "improve.sh library sources improve sub-modules" {
    grep -q "improve/deps.sh" "$PROJECT_ROOT/lib/improve.sh"
    grep -q "improve/args.sh" "$PROJECT_ROOT/lib/improve.sh"
    grep -q "improve/env.sh" "$PROJECT_ROOT/lib/improve.sh"
    grep -q "improve/review.sh" "$PROJECT_ROOT/lib/improve.sh"
    grep -q "improve/execution.sh" "$PROJECT_ROOT/lib/improve.sh"
}

@test "improve sub-modules exist" {
    [ -f "$PROJECT_ROOT/lib/improve/deps.sh" ]
    [ -f "$PROJECT_ROOT/lib/improve/args.sh" ]
    [ -f "$PROJECT_ROOT/lib/improve/env.sh" ]
    [ -f "$PROJECT_ROOT/lib/improve/review.sh" ]
    [ -f "$PROJECT_ROOT/lib/improve/execution.sh" ]
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

@test "improve.sh library implements file-based session tracking (Issue #1106)" {
    # Check for new file-based tracking functions instead of in-memory array
    grep -q 'get_improve_active_issues' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q 'count_improve_active_sessions' "$PROJECT_ROOT/lib/improve/execution.sh"
    
    # Should not have ACTIVE_ISSUE_NUMBERS array anymore
    ! grep -q 'declare -a ACTIVE_ISSUE_NUMBERS' "$PROJECT_ROOT/lib/improve/execution.sh"
}

# ====================
# 関数定義テスト (backward compatibility)
# ====================

@test "improve.sh library provides cleanup_on_exit function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F cleanup_on_exit"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides usage function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F usage"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides parse_improve_arguments function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F parse_improve_arguments"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides setup_improve_environment function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F setup_improve_environment"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides run_review_phase function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F run_review_phase"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides fetch_created_issues function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F fetch_created_issues"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides execute_issues_in_parallel function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F execute_issues_in_parallel"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides wait_for_completion function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F wait_for_completion"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides start_next_iteration function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F start_next_iteration"
    [ "$status" -eq 0 ]
}

@test "improve.sh library provides check_dependencies function" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && declare -F check_dependencies"
    [ "$status" -eq 0 ]
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
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --max-iterations 5 && echo \$_PARSE_max_iterations"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]]
}

@test "parse_improve_arguments handles --max-issues" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --max-issues 10 && echo \$_PARSE_max_issues"
    [ "$status" -eq 0 ]
    [[ "$output" == *"10"* ]]
}

@test "parse_improve_arguments handles --timeout" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --timeout 1800 && echo \$_PARSE_timeout"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1800"* ]]
}

@test "parse_improve_arguments handles --iteration" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --iteration 2 && echo \$_PARSE_iteration"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2"* ]]
}

@test "parse_improve_arguments handles --log-dir" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --log-dir /tmp/logs && echo \$_PARSE_log_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/logs"* ]]
}

@test "parse_improve_arguments defaults log_dir to empty string when not provided" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments && test -z \"\$_PARSE_log_dir\" && echo \"empty\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty"* ]]
}

@test "parse_improve_arguments handles --label" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --label test-session && echo \$_PARSE_session_label"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-session"* ]]
}

@test "parse_improve_arguments handles --dry-run" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --dry-run && echo \$_PARSE_dry_run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "parse_improve_arguments handles --review-only" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --review-only && echo \$_PARSE_review_only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "parse_improve_arguments handles --auto-continue" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --auto-continue && echo \$_PARSE_auto_continue"
    [ "$status" -eq 0 ]
    [[ "$output" == *"true"* ]]
}

@test "parse_improve_arguments handles --verbose" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --verbose && echo LOG_LEVEL=\$LOG_LEVEL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG_LEVEL=DEBUG"* ]]
}

@test "parse_improve_arguments uses default values" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments && echo \$_PARSE_max_iterations \$_PARSE_max_issues \$_PARSE_timeout iteration=\$_PARSE_iteration"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
    [[ "$output" == *"5"* ]]
    [[ "$output" == *"3600"* ]]
    [[ "$output" == *"iteration=1"* ]]
}

@test "parse_improve_arguments handles single quotes in log_dir with direct assignment" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --log-dir \"/tmp/user's-logs\" && echo \$_PARSE_log_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == "/tmp/user's-logs" ]]
}

@test "parse_improve_arguments handles single quotes in session_label with direct assignment" {
    run bash -c "source '$PROJECT_ROOT/lib/improve.sh' && parse_improve_arguments --label \"test's-session\" && echo \$_PARSE_session_label"
    [ "$status" -eq 0 ]
    [[ "$output" == "test's-session" ]]
}

# ====================
# check_dependencies() 関数テスト
# ====================

@test "check_dependencies function exists in deps module" {
    grep -q 'check_improve_dependencies()' "$PROJECT_ROOT/lib/improve/deps.sh" || \
    grep -q 'check_dependencies()' "$PROJECT_ROOT/lib/improve/deps.sh"
}

@test "check_dependencies checks for pi command" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'pi_command'* ]]
}

@test "check_dependencies checks for gh command" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'command -v gh'* ]]
}

@test "check_dependencies checks for jq command" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/deps.sh")
    [[ "$source_content" == *'command -v jq'* ]]
}

# ====================
# ワークフローフェーズテスト
# ====================

@test "improve modules implement 5 phases" {
    # Check in review and execution modules
    grep -q 'PHASE 1' "$PROJECT_ROOT/lib/improve/review.sh"
    grep -q 'PHASE 2' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q 'PHASE 3' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q 'PHASE 4' "$PROJECT_ROOT/lib/improve/execution.sh"
    grep -q 'PHASE 5' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "run_review_phase uses pi --print" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *'--print'* ]]
}

@test "fetch_created_issues uses get_issues_created_after" {
    grep -q 'get_issues_created_after' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "execute_issues_in_parallel uses run.sh --no-attach" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" == *'run.sh'* ]]
    [[ "$source_content" == *'--no-attach'* ]]
}

@test "wait_for_completion uses wait-for-sessions.sh" {
    grep -q 'wait-for-sessions.sh' "$PROJECT_ROOT/lib/improve/execution.sh"
}

@test "start_next_iteration uses exec for recursion" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" == *'exec "$0"'* ]]
}

# ====================
# cleanup_on_exit() 関数テスト
# ====================

@test "cleanup_on_exit function handles active sessions (Issue #1106)" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    # Should use file-based tracking instead of ACTIVE_ISSUE_NUMBERS
    [[ "$source_content" == *'get_improve_active_issues'* ]]
    [[ "$source_content" == *'cleanup.sh'* ]]
}

@test "cleanup_on_exit uses --force flag" {
    grep -q 'cleanup.sh.*--force' "$PROJECT_ROOT/lib/improve/execution.sh"
}

# ====================
# improve_main() 関数テスト
# ====================

@test "improve_main sets up trap (Issue #1106)" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    # Trap now passes session_label parameter for file-based tracking
    [[ "$source_content" == *'trap'* ]]
    [[ "$source_content" == *'cleanup_improve_on_exit'* ]]
}

@test "improve_main calls all workflow phases" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve.sh")
    # Check for phase function calls (new function names with _improve_ prefix)
    [[ "$source_content" == *'parse_improve_arguments'* ]]
    [[ "$source_content" == *'setup_improve_environment'* ]]
    [[ "$source_content" == *'run_improve_review_phase'* ]]
    [[ "$source_content" == *'fetch_improve_created_issues'* ]]
    [[ "$source_content" == *'execute_improve_issues_in_parallel'* ]]
    [[ "$source_content" == *'wait_for_improve_completion'* ]]
    [[ "$source_content" == *'start_improve_next_iteration'* ]]
}

# ====================
# セッションラベル機能テスト
# ====================

@test "setup_improve_environment generates session label" {
    grep -q 'generate_improve_session_label' "$PROJECT_ROOT/lib/improve/env.sh"
}

@test "setup_improve_environment creates GitHub label" {
    grep -q 'create_label_if_not_exists' "$PROJECT_ROOT/lib/improve/env.sh"
}

@test "setup_improve_environment skips label creation in dry-run mode" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/env.sh")
    [[ "$source_content" == *'dry_run" != "true"'* ]]
}

@test "setup_improve_environment handles single quotes in session_label with direct assignment" {
    # Mock dependencies
    mock_gh
    mock_date() { echo "2026-02-06T12:00:00Z"; }
    export -f mock_date
    
    run bash -c "
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        source '$PROJECT_ROOT/lib/improve/env.sh'
        
        # Override dependencies
        date() { mock_date; }
        create_label_if_not_exists() { return 0; }
        check_improve_dependencies() { return 0; }
        load_config() { return 0; }
        
        # Call with single quote in label
        setup_improve_environment 1 3 \"test's-label\" /tmp/logs false false
        echo \"\$_PARSE_session_label\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"test's-label"* ]]
}

@test "setup_improve_environment handles single quotes in log_file with direct assignment" {
    # Mock dependencies
    mock_gh
    mock_date() { echo "2026-02-06T12:00:00Z"; }
    export -f mock_date
    
    run bash -c "
        source '$PROJECT_ROOT/lib/config.sh'
        source '$PROJECT_ROOT/lib/log.sh'
        source '$PROJECT_ROOT/lib/github.sh'
        source '$PROJECT_ROOT/lib/improve/env.sh'
        
        # Override dependencies
        date() { mock_date; }
        create_label_if_not_exists() { return 0; }
        check_improve_dependencies() { return 0; }
        load_config() { return 0; }
        
        # Call with single quote in log_dir
        setup_improve_environment 1 3 test-label \"/tmp/user's-logs\" false false
        echo \"\$_PARSE_log_file\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/user's-logs/"* ]]
}

@test "setup_improve_environment populates log_dir from config when empty" {
    # Verify that the code checks for empty log_dir and calls get_config
    source_content=$(cat "$PROJECT_ROOT/lib/improve/env.sh")
    [[ "$source_content" == *'[[ -z "$log_dir" ]]'* ]]
    [[ "$source_content" == *'get_config improve_logs_dir'* ]]
}

# ====================
# エラーハンドリングテスト
# ====================

@test "run_review_phase handles pi command failure" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *'pi command returned non-zero'* ]]
}

@test "fetch_created_issues handles no issues gracefully" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" == *'No new Issues created'* ]]
}

@test "execute_issues_in_parallel handles session start failure" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/execution.sh")
    [[ "$source_content" == *'Failed to start session'* ]]
}

# ====================
# --dry-run / --review-only モードテスト
# ====================

@test "run_review_phase supports dry-run mode" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *'Dry-run mode complete'* ]]
    [[ "$source_content" == *'No Issues were created'* ]]
}

@test "run_review_phase supports review-only mode" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *'Review-only mode complete'* ]]
}

@test "dry-run mode exits early" {
    source_content=$(cat "$PROJECT_ROOT/lib/improve/review.sh")
    [[ "$source_content" == *'Issueは作成しないでください'* ]]
}

# ====================
# 行数テスト（リファクタリング後）
# ====================

@test "lib/improve.sh is now smaller after refactoring" {
    line_count=$(wc -l < "$PROJECT_ROOT/lib/improve.sh")
    # Should be less than 200 lines after refactoring
    [ "$line_count" -lt 200 ]
}

@test "each improve sub-module is under 350 lines (Issue #1106)" {
    # Increased from 300 to 350 due to file-based session tracking refactoring
    for module in deps args env review execution; do
        line_count=$(wc -l < "$PROJECT_ROOT/lib/improve/${module}.sh")
        [ "$line_count" -lt 350 ]
    done
}

@test "total lines in improve modules is reasonable (Issue #1106)" {
    total_lines=$(cat "$PROJECT_ROOT/lib/improve.sh" "$PROJECT_ROOT/lib/improve"/*.sh | wc -l)
    # Increased from 900 to 950 due to file-based session tracking refactoring
    # (added helper functions for robustness and concurrent execution support)
    [ "$total_lines" -lt 950 ]
}
