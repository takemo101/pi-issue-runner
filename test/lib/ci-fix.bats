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

@test "detect_project_type function exists" {
    declare -f detect_project_type
}

@test "detect_project_type returns rust for Cargo.toml" {
    mkdir -p "$BATS_TEST_TMPDIR/rust-project"
    touch "$BATS_TEST_TMPDIR/rust-project/Cargo.toml"
    
    run detect_project_type "$BATS_TEST_TMPDIR/rust-project"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

@test "detect_project_type returns node for package.json" {
    mkdir -p "$BATS_TEST_TMPDIR/node-project"
    touch "$BATS_TEST_TMPDIR/node-project/package.json"
    
    run detect_project_type "$BATS_TEST_TMPDIR/node-project"
    [ "$status" -eq 0 ]
    [ "$output" = "node" ]
}

@test "detect_project_type returns python for pyproject.toml" {
    mkdir -p "$BATS_TEST_TMPDIR/python-project"
    touch "$BATS_TEST_TMPDIR/python-project/pyproject.toml"
    
    run detect_project_type "$BATS_TEST_TMPDIR/python-project"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type returns python for setup.py" {
    mkdir -p "$BATS_TEST_TMPDIR/python-project-setup"
    touch "$BATS_TEST_TMPDIR/python-project-setup/setup.py"
    
    run detect_project_type "$BATS_TEST_TMPDIR/python-project-setup"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type returns go for go.mod" {
    mkdir -p "$BATS_TEST_TMPDIR/go-project"
    touch "$BATS_TEST_TMPDIR/go-project/go.mod"
    
    run detect_project_type "$BATS_TEST_TMPDIR/go-project"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

@test "detect_project_type returns bash for .bats files" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-project"
    touch "$BATS_TEST_TMPDIR/bash-project/test.bats"
    
    run detect_project_type "$BATS_TEST_TMPDIR/bash-project"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "detect_project_type returns bash for test/test_helper.bash" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-project-helper/test"
    touch "$BATS_TEST_TMPDIR/bash-project-helper/test/test_helper.bash"
    
    run detect_project_type "$BATS_TEST_TMPDIR/bash-project-helper"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "detect_project_type returns unknown for unrecognized project" {
    mkdir -p "$BATS_TEST_TMPDIR/unknown-project"
    
    run detect_project_type "$BATS_TEST_TMPDIR/unknown-project"
    [ "$status" -eq 1 ]
    [ "$output" = "unknown" ]
}

@test "detect_project_type prioritizes rust over node" {
    mkdir -p "$BATS_TEST_TMPDIR/mixed-project"
    touch "$BATS_TEST_TMPDIR/mixed-project/Cargo.toml"
    touch "$BATS_TEST_TMPDIR/mixed-project/package.json"
    
    run detect_project_type "$BATS_TEST_TMPDIR/mixed-project"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

@test "detect_project_type prioritizes node over python" {
    mkdir -p "$BATS_TEST_TMPDIR/mixed-node-python"
    touch "$BATS_TEST_TMPDIR/mixed-node-python/package.json"
    touch "$BATS_TEST_TMPDIR/mixed-node-python/pyproject.toml"
    
    run detect_project_type "$BATS_TEST_TMPDIR/mixed-node-python"
    [ "$status" -eq 0 ]
    [ "$output" = "node" ]
}

@test "detect_project_type prioritizes python over go" {
    mkdir -p "$BATS_TEST_TMPDIR/mixed-python-go"
    touch "$BATS_TEST_TMPDIR/mixed-python-go/pyproject.toml"
    touch "$BATS_TEST_TMPDIR/mixed-python-go/go.mod"
    
    run detect_project_type "$BATS_TEST_TMPDIR/mixed-python-go"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "detect_project_type prioritizes go over bash" {
    mkdir -p "$BATS_TEST_TMPDIR/mixed-go-bash"
    touch "$BATS_TEST_TMPDIR/mixed-go-bash/go.mod"
    touch "$BATS_TEST_TMPDIR/mixed-go-bash/test.bats"
    
    run detect_project_type "$BATS_TEST_TMPDIR/mixed-go-bash"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

# ===================
# try_fix_format 汎用化テスト
# ===================

@test "try_fix_format detects project type and returns appropriate status" {
    # Rustプロジェクトの場合（cargoがない環境では失敗する）
    mkdir -p "$BATS_TEST_TMPDIR/rust-format-test"
    touch "$BATS_TEST_TMPDIR/rust-format-test/Cargo.toml"
    
    run try_fix_format "$BATS_TEST_TMPDIR/rust-format-test"
    # cargoがない場合は1、ある場合は0か1（フォーマット結果による）
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "try_fix_format returns 2 for unknown project type" {
    mkdir -p "$BATS_TEST_TMPDIR/unknown-format-test"
    
    run try_fix_format "$BATS_TEST_TMPDIR/unknown-format-test"
    [ "$status" -eq 2 ]
}

# ===================
# try_fix_lint 汎用化テスト
# ===================

@test "try_fix_lint detects project type and returns appropriate status" {
    # Rustプロジェクトの場合（cargoがない環境では失敗する）
    mkdir -p "$BATS_TEST_TMPDIR/rust-lint-test"
    touch "$BATS_TEST_TMPDIR/rust-lint-test/Cargo.toml"
    
    run try_fix_lint "$BATS_TEST_TMPDIR/rust-lint-test"
    # cargoがない場合は1、ある場合は0か1（lint結果による）
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "try_fix_lint returns 2 for unknown project type" {
    mkdir -p "$BATS_TEST_TMPDIR/unknown-lint-test"
    
    run try_fix_lint "$BATS_TEST_TMPDIR/unknown-lint-test"
    [ "$status" -eq 2 ]
}

@test "try_fix_lint returns 2 for bash projects (shellcheck does not support auto-fix)" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-lint-test"
    touch "$BATS_TEST_TMPDIR/bash-lint-test/test.bats"
    
    run try_fix_lint "$BATS_TEST_TMPDIR/bash-lint-test"
    [ "$status" -eq 2 ]
}

# ===================
# run_local_validation マルチプロジェクト対応テスト
# ===================

@test "run_local_validation detects rust project and validates with cargo" {
    mkdir -p "$BATS_TEST_TMPDIR/rust-validation"
    touch "$BATS_TEST_TMPDIR/rust-validation/Cargo.toml"
    
    run run_local_validation "$BATS_TEST_TMPDIR/rust-validation"
    # cargoがない場合は0（スキップ）、ある場合は0か1（検証結果による）
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    # ログにRustプロジェクトが検出されたことを確認
    [[ "$output" == *"rust"* ]]
}

@test "run_local_validation detects node project and validates with npm" {
    mkdir -p "$BATS_TEST_TMPDIR/node-validation"
    cat > "$BATS_TEST_TMPDIR/node-validation/package.json" << 'EOF'
{
  "name": "test",
  "scripts": {
    "lint": "echo 'lint ok'",
    "test": "echo 'test ok'"
  }
}
EOF
    
    run run_local_validation "$BATS_TEST_TMPDIR/node-validation"
    # npmがある場合は検証を実行、ない場合は0（スキップ）
    [ "$status" -eq 0 ]
    [[ "$output" == *"node"* ]]
}

@test "run_local_validation detects python project and validates with flake8/pytest" {
    mkdir -p "$BATS_TEST_TMPDIR/python-validation"
    touch "$BATS_TEST_TMPDIR/python-validation/pyproject.toml"
    
    run run_local_validation "$BATS_TEST_TMPDIR/python-validation"
    # flake8/pytestがない場合は0（スキップ）、ある場合は検証結果による
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    [[ "$output" == *"python"* ]]
}

@test "run_local_validation detects go project and validates with go vet/test" {
    mkdir -p "$BATS_TEST_TMPDIR/go-validation"
    touch "$BATS_TEST_TMPDIR/go-validation/go.mod"
    
    run run_local_validation "$BATS_TEST_TMPDIR/go-validation"
    # goがない場合は0（スキップ）、ある場合は検証結果による
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    [[ "$output" == *"go"* ]]
}

@test "run_local_validation detects bash project and validates with shellcheck/bats" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-validation"
    touch "$BATS_TEST_TMPDIR/bash-validation/test.bats"
    
    run run_local_validation "$BATS_TEST_TMPDIR/bash-validation"
    # shellcheck/batsがない場合は0（スキップ）、ある場合は検証結果による
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
    [[ "$output" == *"bash"* ]]
}

@test "run_local_validation skips validation for unknown project type" {
    mkdir -p "$BATS_TEST_TMPDIR/unknown-validation"
    
    run run_local_validation "$BATS_TEST_TMPDIR/unknown-validation"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unknown"* ]]
    [[ "$output" == *"Skipping validation"* ]]
}

@test "run_local_validation skips npm lint if not configured in package.json" {
    mkdir -p "$BATS_TEST_TMPDIR/node-no-lint"
    cat > "$BATS_TEST_TMPDIR/node-no-lint/package.json" << 'EOF'
{
  "name": "test",
  "scripts": {}
}
EOF
    
    run run_local_validation "$BATS_TEST_TMPDIR/node-no-lint"
    [ "$status" -eq 0 ]
    # lintスクリプトがないのでスキップされる
    [[ "$output" != *"Running npm run lint"* ]]
}

@test "run_local_validation skips npm test if not configured in package.json" {
    mkdir -p "$BATS_TEST_TMPDIR/node-no-test"
    cat > "$BATS_TEST_TMPDIR/node-no-test/package.json" << 'EOF'
{
  "name": "test",
  "scripts": {}
}
EOF
    
    run run_local_validation "$BATS_TEST_TMPDIR/node-no-test"
    [ "$status" -eq 0 ]
    # testスクリプトがないのでスキップされる
    [[ "$output" != *"Running npm test"* ]]
}
