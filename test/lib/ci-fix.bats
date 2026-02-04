#!/usr/bin/env bats
# ci-fix.bats - CI自動修正機能のテスト
#
# 注意: このテストファイルは ci-fix.sh のコア機能のみをテストします。
# 分割されたモジュールのテストは以下のファイルを参照:
#   - ci-monitor.bats: CI状態監視
#   - ci-classifier.bats: 失敗タイプ分類
#   - ci-retry.bats: リトライ管理

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 状態ファイルのクリーンアップ（状態ディレクトリ内のファイルを削除）
    rm -rf /tmp/pi-runner-state/ci-retry-*
    
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/github.sh"
    source "$PROJECT_ROOT/lib/ci-fix.sh"
}

teardown() {
    # リトライ状態ファイルのクリーンアップ（状態ディレクトリ内のファイルを削除）
    rm -rf /tmp/pi-runner-state/ci-retry-*
    
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# 定数テスト（後方互換性）
# ===================

@test "ci-fix exports constants from dependent modules" {
    # ci-monitor.sh の定数
    [[ "$CI_POLL_INTERVAL" == "30" ]]
    [[ "$CI_TIMEOUT" == "600" ]]
    
    # ci-retry.sh の定数
    [[ "$MAX_RETRY_COUNT" == "3" ]]
    
    # ci-classifier.sh の定数
    [[ "$FAILURE_TYPE_LINT" == "lint" ]]
    [[ "$FAILURE_TYPE_FORMAT" == "format" ]]
    [[ "$FAILURE_TYPE_TEST" == "test" ]]
    [[ "$FAILURE_TYPE_BUILD" == "build" ]]
    [[ "$FAILURE_TYPE_UNKNOWN" == "unknown" ]]
}

# ===================
# try_auto_fix テスト（モック使用）
# ===================

@test "try_auto_fix returns 2 for test failures (requires AI)" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_auto_fix "test" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix returns 2 for build errors (requires AI)" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_auto_fix "build" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "try_auto_fix returns 2 for unknown failure type" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_auto_fix "unknown" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

# ===================
# 関数存在確認（統合テスト）
# ===================

@test "all ci-fix functions are available after sourcing" {
    # ci-monitor.sh の関数
    declare -f wait_for_ci_completion
    declare -f get_pr_checks_status
    
    # ci-classifier.sh の関数
    declare -f get_failed_ci_logs
    declare -f classify_ci_failure
    
    # ci-retry.sh の関数
    declare -f get_retry_state_file
    declare -f get_retry_count
    declare -f increment_retry_count
    declare -f reset_retry_count
    declare -f should_continue_retry
    
    # ci-fix.sh の関数
    declare -f try_auto_fix
    declare -f try_fix_lint
    declare -f try_fix_format
    declare -f run_local_validation
    declare -f escalate_to_manual
    declare -f mark_pr_as_draft
    declare -f add_pr_comment
    declare -f handle_ci_failure
}

# ===================
# モジュール依存関係テスト
# ===================

@test "ci-fix.sh sources all required modules" {
    # 各モジュールの定数が利用可能
    [[ -n "$CI_POLL_INTERVAL" ]]
    [[ -n "$MAX_RETRY_COUNT" ]]
    [[ -n "$FAILURE_TYPE_FORMAT" ]]
}

# ===================
# detect_project_type テスト
# ===================

@test "detect_project_type detects rust project" {
    cd "$BATS_TEST_TMPDIR"
    touch Cargo.toml
    
    run detect_project_type "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

@test "detect_project_type detects node project" {
    cd "$BATS_TEST_TMPDIR"
    touch package.json
    
    run detect_project_type "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "node" ]
}

@test "detect_project_type detects python project with pyproject.toml" {
    cd "$BATS_TEST_TMPDIR"
    touch pyproject.toml
    
    run detect_project_type "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type detects python project with setup.py" {
    cd "$BATS_TEST_TMPDIR"
    touch setup.py
    
    run detect_project_type "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type detects bash-bats project" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p test
    touch test/test_helper.bash
    
    run detect_project_type "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "bash-bats" ]
}

@test "detect_project_type returns unknown for unrecognized project" {
    cd "$BATS_TEST_TMPDIR"
    
    run detect_project_type "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "detect_project_type defaults to current directory" {
    # 実際のプロジェクトルートで実行（test/test_helper.bash が存在する）
    cd "$PROJECT_ROOT"
    
    run detect_project_type
    [ "$status" -eq 0 ]
    [ "$output" = "bash-bats" ]
}

# ===================
# get_lint_fix_command テスト
# ===================

@test "get_lint_fix_command returns cargo command for rust" {
    run get_lint_fix_command "rust"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cargo clippy" ]]
}

@test "get_lint_fix_command returns npm/eslint command for node" {
    run get_lint_fix_command "node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "eslint" ]]
}

@test "get_lint_fix_command returns pylint command for python" {
    run get_lint_fix_command "python"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pylint" ]]
}

@test "get_lint_fix_command returns shellcheck command for bash-bats" {
    run get_lint_fix_command "bash-bats"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "shellcheck" ]]
}

@test "get_lint_fix_command fails for unknown project type" {
    run get_lint_fix_command "unknown"
    [ "$status" -eq 1 ]
}

# ===================
# get_format_fix_command テスト
# ===================

@test "get_format_fix_command returns cargo fmt for rust" {
    run get_format_fix_command "rust"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cargo fmt" ]]
}

@test "get_format_fix_command returns prettier for node" {
    run get_format_fix_command "node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "prettier" ]]
}

@test "get_format_fix_command returns black for python" {
    run get_format_fix_command "python"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "black" ]]
}

@test "get_format_fix_command returns shfmt for bash-bats" {
    run get_format_fix_command "bash-bats"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "shfmt" ]]
}

@test "get_format_fix_command fails for unknown project type" {
    run get_format_fix_command "unknown"
    [ "$status" -eq 1 ]
}

# ===================
# get_validation_command テスト
# ===================

@test "get_validation_command returns cargo commands for rust" {
    run get_validation_command "rust"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cargo clippy" ]]
    [[ "$output" =~ "cargo test" ]]
}

@test "get_validation_command returns npm commands for node" {
    run get_validation_command "node"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "npm run lint" ]]
    [[ "$output" =~ "npm test" ]]
}

@test "get_validation_command returns python commands for python" {
    run get_validation_command "python"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pylint" ]]
    [[ "$output" =~ "pytest" ]]
}

@test "get_validation_command returns shellcheck+bats for bash-bats" {
    run get_validation_command "bash-bats"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "shellcheck" ]]
    [[ "$output" =~ "bats" ]]
}

@test "get_validation_command fails for unknown project type" {
    run get_validation_command "unknown"
    [ "$status" -eq 1 ]
}

# ===================
# try_fix_lint with project detection テスト
# ===================

@test "try_fix_lint returns 2 for unknown project type" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_fix_lint "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown project type" ]]
}

@test "try_fix_lint detects project type and attempts fix" {
    cd "$BATS_TEST_TMPDIR"
    touch Cargo.toml
    
    run try_fix_lint "$BATS_TEST_TMPDIR"
    # cargo がインストールされていない場合は失敗するが、検出はされる
    [[ "$output" =~ "Detected project type: rust" ]]
}

# ===================
# try_fix_format with project detection テスト
# ===================

@test "try_fix_format returns 2 for unknown project type" {
    cd "$BATS_TEST_TMPDIR"
    
    run try_fix_format "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown project type" ]]
}

@test "try_fix_format detects project type and attempts fix" {
    cd "$BATS_TEST_TMPDIR"
    touch package.json
    
    run try_fix_format "$BATS_TEST_TMPDIR"
    # npm がインストールされていない場合でも、検出はされる
    [[ "$output" =~ "Detected project type: node" ]]
}

# ===================
# run_local_validation with project detection テスト
# ===================

@test "run_local_validation returns 0 for unknown project type" {
    cd "$BATS_TEST_TMPDIR"
    
    run run_local_validation "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unknown project type" ]]
}

@test "run_local_validation detects project type" {
    cd "$BATS_TEST_TMPDIR"
    touch pyproject.toml
    
    run run_local_validation "$BATS_TEST_TMPDIR"
    # Python ツールがインストールされていない場合でも、検出はされる
    [[ "$output" =~ "Detected project type: python" ]]
}
