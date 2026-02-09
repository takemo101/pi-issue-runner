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
# mark_pr_as_draft 動作テスト
# ===================

@test "mark_pr_as_draft calls gh pr ready --undo with correct PR number" {
    # ghモックを作成（pr ready --undo を記録）
    local mock_log="$BATS_TEST_TMPDIR/gh_calls.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" >> "$mock_log"
case "\$*" in
    "pr ready"*"--undo"*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run mark_pr_as_draft 123
    [ "$status" -eq 0 ]
    # ghが正しい引数で呼ばれたことを確認
    grep -q "pr ready 123 --undo" "$mock_log"
}

@test "mark_pr_as_draft returns 1 when gh pr ready --undo fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run mark_pr_as_draft 456
    [ "$status" -eq 1 ]
}

@test "mark_pr_as_draft returns 1 when gh CLI is not found" {
    # ghを見つからなくする（基本コマンドは残す）
    mkdir -p "$BATS_TEST_TMPDIR/no-gh-bin"
    ln -sf "$(command -v bash)" "$BATS_TEST_TMPDIR/no-gh-bin/bash"
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-gh-bin"

    run mark_pr_as_draft 789
    export PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh CLI not found"* ]]
}

# ===================
# add_pr_comment 動作テスト
# ===================

@test "add_pr_comment calls gh pr comment with correct PR number" {
    local mock_log="$BATS_TEST_TMPDIR/gh_calls.log"
    local mock_stdin="$BATS_TEST_TMPDIR/gh_stdin.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" >> "$mock_log"
cat > "$mock_stdin"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run add_pr_comment 123 "CI fix failed"
    [ "$status" -eq 0 ]
    # gh pr comment が正しいPR番号で呼ばれた
    grep -q "pr comment 123 -F -" "$mock_log"
    # コメント内容がstdinで渡された
    grep -q "CI fix failed" "$mock_stdin"
}

@test "add_pr_comment returns 1 when gh pr comment fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
cat > /dev/null  # stdin を消費
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run add_pr_comment 456 "Some comment"
    [ "$status" -eq 1 ]
}

@test "add_pr_comment returns 1 when gh CLI is not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-gh-bin"
    ln -sf "$(command -v bash)" "$BATS_TEST_TMPDIR/no-gh-bin/bash"
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-gh-bin"

    run add_pr_comment 789 "Some comment"
    export PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh CLI not found"* ]]
}

# ===================
# escalate_to_manual 動作テスト
# ===================

@test "escalate_to_manual calls mark_pr_as_draft and add_pr_comment" {
    local mock_log="$BATS_TEST_TMPDIR/gh_calls.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" >> "$mock_log"
case "\$*" in
    "pr ready"*"--undo"*)
        exit 0
        ;;
    "pr comment"*)
        cat > /dev/null  # stdin を消費
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run escalate_to_manual 42 "Build failed: error[E0308]"
    [ "$status" -eq 0 ]
    # mark_pr_as_draft が呼ばれた
    grep -q "pr ready 42 --undo" "$mock_log"
    # add_pr_comment が呼ばれた
    grep -q "pr comment 42 -F -" "$mock_log"
}

@test "escalate_to_manual includes failure log in comment" {
    local mock_stdin="$BATS_TEST_TMPDIR/gh_stdin.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << MOCK_EOF
#!/usr/bin/env bash
case "\$*" in
    "pr ready"*"--undo"*)
        exit 0
        ;;
    "pr comment"*)
        cat > "$mock_stdin"
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run escalate_to_manual 42 "test failure: expected 0 got 1"
    [ "$status" -eq 0 ]
    # コメントに失敗ログが含まれる
    grep -q "test failure: expected 0 got 1" "$mock_stdin"
    # エスカレーションメッセージが含まれる
    grep -q "エスカレーション" "$mock_stdin"
}

@test "escalate_to_manual succeeds even with empty failure log" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "pr ready"*"--undo"*)
        exit 0
        ;;
    "pr comment"*)
        cat > /dev/null
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gh"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run escalate_to_manual 42 ""
    [ "$status" -eq 0 ]
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

# ===================
# Bash言語固有関数テスト
# ===================

@test "_fix_lint_bash returns 2 (auto-fix not supported)" {
    run _fix_lint_bash
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not support auto-fix"* ]]
}

@test "_fix_format_bash uses shfmt when available" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-fmt/scripts"
    echo '#!/bin/bash' > "$BATS_TEST_TMPDIR/bash-fmt/scripts/run.sh"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shfmt" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "shfmt executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shfmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-fmt"
    run _fix_format_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"shfmt"* ]]
}

@test "_fix_format_bash returns 1 when shfmt fails" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-fmt2/scripts"
    echo '#!/bin/bash' > "$BATS_TEST_TMPDIR/bash-fmt2/scripts/run.sh"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shfmt" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shfmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-fmt2"
    run _fix_format_bash
    [ "$status" -eq 1 ]
}

@test "_fix_format_bash returns 2 when no .sh files found" {
    mkdir -p "$BATS_TEST_TMPDIR/empty-proj"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shfmt" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "shfmt executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shfmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/empty-proj"
    run _fix_format_bash
    [ "$status" -eq 2 ]
    [[ "$output" == *"No .sh files found"* ]]
}

@test "_fix_format_bash excludes .git directory" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-fmt-git/.git/hooks"
    echo '#!/bin/bash' > "$BATS_TEST_TMPDIR/bash-fmt-git/.git/hooks/pre-commit.sh"
    mkdir -p "$BATS_TEST_TMPDIR/bash-fmt-git/scripts"
    echo '#!/bin/bash' > "$BATS_TEST_TMPDIR/bash-fmt-git/scripts/run.sh"
    
    local shfmt_args_file="$BATS_TEST_TMPDIR/shfmt_args.log"
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shfmt" << MOCK_EOF
#!/usr/bin/env bash
echo "\$*" >> "$shfmt_args_file"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shfmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-fmt-git"
    run _fix_format_bash
    [ "$status" -eq 0 ]
    # .git内のファイルがshfmtに渡されていないことを確認
    ! grep -q ".git" "$shfmt_args_file"
}

@test "_fix_format_bash returns 2 when shfmt not found" {
    # Hide shfmt from PATH
    mkdir -p "$BATS_TEST_TMPDIR/no-shfmt"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-shfmt/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-shfmt"

    run _fix_format_bash
    export PATH="$saved_path"
    [ "$status" -eq 2 ]
    [[ "$output" == *"shfmt not found"* ]]
}

@test "_validate_bash runs shellcheck when available" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-proj/scripts" "$BATS_TEST_TMPDIR/bash-proj/lib"
    touch "$BATS_TEST_TMPDIR/bash-proj/scripts/run.sh" "$BATS_TEST_TMPDIR/bash-proj/lib/log.sh"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "shellcheck OK"
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "bats OK"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-proj"
    run _validate_bash
    [ "$status" -eq 0 ]
}

@test "_validate_bash returns 1 when shellcheck fails" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-proj2/scripts" "$BATS_TEST_TMPDIR/bash-proj2/lib"
    touch "$BATS_TEST_TMPDIR/bash-proj2/scripts/run.sh" "$BATS_TEST_TMPDIR/bash-proj2/lib/log.sh"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "SC2086: Double quote to prevent globbing" >&2
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-proj2"
    run _validate_bash
    [ "$status" -eq 1 ]
}

@test "_validate_bash skips shellcheck when no .sh files found" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-proj-nosh/test"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "shellcheck should not run"
exit 1
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-proj-nosh"
    run _validate_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"No .sh files found"* ]]
}

@test "_validate_bash returns 1 when bats fails" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-proj3/scripts" "$BATS_TEST_TMPDIR/bash-proj3/lib" "$BATS_TEST_TMPDIR/bash-proj3/test"
    touch "$BATS_TEST_TMPDIR/bash-proj3/scripts/run.sh" "$BATS_TEST_TMPDIR/bash-proj3/lib/log.sh"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "1 test failed"
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-proj3"
    run _validate_bash
    [ "$status" -eq 1 ]
}

@test "_validate_bash skips bats when no test directory exists" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-proj-notest/scripts"
    touch "$BATS_TEST_TMPDIR/bash-proj-notest/scripts/run.sh"

    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "bats should not be called"
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-proj-notest"
    run _validate_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"No test directory found"* ]]
}

@test "_validate_bash uses tests/ directory when test/ does not exist" {
    mkdir -p "$BATS_TEST_TMPDIR/bash-proj-tests/scripts" "$BATS_TEST_TMPDIR/bash-proj-tests/tests"
    touch "$BATS_TEST_TMPDIR/bash-proj-tests/scripts/run.sh"

    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "bats OK on tests/"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/bash-proj-tests"
    run _validate_bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"Running bats in tests/"* ]]
}

# ===================
# Go言語固有関数テスト
# ===================

@test "_fix_lint_go uses golangci-lint when available" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/golangci-lint" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "golangci-lint executed with: $*"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/golangci-lint"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_lint_go
    [ "$status" -eq 0 ]
    [[ "$output" == *"golangci-lint"* ]]
}

@test "_fix_lint_go returns 1 when golangci-lint fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/golangci-lint" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/golangci-lint"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_lint_go
    [ "$status" -eq 1 ]
}

@test "_fix_lint_go returns 2 when golangci-lint not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-golangci"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-golangci/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-golangci"

    run _fix_lint_go
    export PATH="$saved_path"
    [ "$status" -eq 2 ]
    [[ "$output" == *"golangci-lint not found"* ]]
}

@test "_fix_format_go uses gofmt when available" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gofmt" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "gofmt executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gofmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_go
    [ "$status" -eq 0 ]
    [[ "$output" == *"gofmt"* ]]
}

@test "_fix_format_go returns 1 when gofmt fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/gofmt" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/gofmt"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_go
    [ "$status" -eq 1 ]
}

@test "_fix_format_go returns 1 when gofmt not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-gofmt"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-gofmt/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-gofmt"

    run _fix_format_go
    export PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gofmt not found"* ]]
}

@test "_validate_go runs go vet and go test" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/go" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "go $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/go"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_go
    [ "$status" -eq 0 ]
    [[ "$output" == *"go vet"* ]]
    [[ "$output" == *"go test"* ]]
}

@test "_validate_go returns 1 when go vet fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/go" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "vet" ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/go"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_go
    [ "$status" -eq 1 ]
}

@test "_validate_go returns 1 when go test fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/go" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "test" ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/go"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_go
    [ "$status" -eq 1 ]
}

@test "_validate_go skips when go not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-go"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-go/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-go"

    run _validate_go
    export PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"go not found"* ]]
}

# ===================
# Node言語固有関数テスト
# ===================

@test "_fix_lint_node uses npm run lint:fix when available" {
    mkdir -p "$BATS_TEST_TMPDIR/node-proj"
    cat > "$BATS_TEST_TMPDIR/node-proj/package.json" << 'EOF'
{ "scripts": { "lint:fix": "eslint --fix ." } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "npm $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-proj"
    run _fix_lint_node
    [ "$status" -eq 0 ]
    [[ "$output" == *"lint:fix"* ]] || [[ "$output" == *"Lint fix applied"* ]]
}

@test "_fix_lint_node returns 1 when npm run lint:fix fails" {
    mkdir -p "$BATS_TEST_TMPDIR/node-proj2"
    cat > "$BATS_TEST_TMPDIR/node-proj2/package.json" << 'EOF'
{ "scripts": { "lint:fix": "eslint --fix ." } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-proj2"
    run _fix_lint_node
    [ "$status" -eq 1 ]
}

@test "_fix_lint_node falls back to npx eslint --fix" {
    mkdir -p "$BATS_TEST_TMPDIR/node-proj3"
    # No lint:fix in package.json
    cat > "$BATS_TEST_TMPDIR/node-proj3/package.json" << 'EOF'
{ "scripts": {} }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npx" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "npx $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npx"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-proj3"
    run _fix_lint_node
    [ "$status" -eq 0 ]
    [[ "$output" == *"eslint"* ]] || [[ "$output" == *"ESLint fix applied"* ]]
}

@test "_fix_format_node uses npm run format when available" {
    mkdir -p "$BATS_TEST_TMPDIR/node-fmt"
    cat > "$BATS_TEST_TMPDIR/node-fmt/package.json" << 'EOF'
{ "scripts": { "format": "prettier --write ." } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "npm $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-fmt"
    run _fix_format_node
    [ "$status" -eq 0 ]
    [[ "$output" == *"Format fix applied"* ]] || [[ "$output" == *"format"* ]]
}

@test "_fix_format_node returns 1 when npm run format fails" {
    mkdir -p "$BATS_TEST_TMPDIR/node-fmt2"
    cat > "$BATS_TEST_TMPDIR/node-fmt2/package.json" << 'EOF'
{ "scripts": { "format": "prettier --write ." } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-fmt2"
    run _fix_format_node
    [ "$status" -eq 1 ]
}

@test "_fix_format_node falls back to npx prettier --write" {
    mkdir -p "$BATS_TEST_TMPDIR/node-fmt3"
    cat > "$BATS_TEST_TMPDIR/node-fmt3/package.json" << 'EOF'
{ "scripts": {} }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npx" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "npx $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npx"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-fmt3"
    run _fix_format_node
    [ "$status" -eq 0 ]
    [[ "$output" == *"prettier"* ]] || [[ "$output" == *"Prettier fix applied"* ]]
}

@test "_validate_node runs lint and test scripts" {
    mkdir -p "$BATS_TEST_TMPDIR/node-val"
    cat > "$BATS_TEST_TMPDIR/node-val/package.json" << 'EOF'
{ "name": "test", "scripts": { "lint": "eslint .", "test": "jest" } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "npm $* OK"
exit 0
MOCK_EOF
    # jqモック: jq -e '.scripts.lint' のチェックを通す
    cat > "$BATS_TEST_TMPDIR/mocks/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
# jq -e '.scripts.lint' or '.scripts.test' - both exist
if [[ "$2" == ".scripts.lint" ]] || [[ "$2" == ".scripts.test" ]]; then
    echo '"found"'
    exit 0
fi
# Default: delegate to real jq if available
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm" "$BATS_TEST_TMPDIR/mocks/jq"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-val"
    run _validate_node
    [ "$status" -eq 0 ]
}

@test "_validate_node returns 1 when npm run lint fails" {
    mkdir -p "$BATS_TEST_TMPDIR/node-val2"
    cat > "$BATS_TEST_TMPDIR/node-val2/package.json" << 'EOF'
{ "name": "test", "scripts": { "lint": "eslint ." } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"lint"* ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == ".scripts.lint" ]]; then
    echo '"found"'
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm" "$BATS_TEST_TMPDIR/mocks/jq"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-val2"
    run _validate_node
    [ "$status" -eq 1 ]
}

@test "_validate_node returns 1 when npm test fails" {
    mkdir -p "$BATS_TEST_TMPDIR/node-val3"
    cat > "$BATS_TEST_TMPDIR/node-val3/package.json" << 'EOF'
{ "name": "test", "scripts": { "test": "jest" } }
EOF
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/npm" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$*" == *"test"* ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/jq" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$2" == ".scripts.test" ]]; then
    echo '"found"'
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/npm" "$BATS_TEST_TMPDIR/mocks/jq"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    cd "$BATS_TEST_TMPDIR/node-val3"
    run _validate_node
    [ "$status" -eq 1 ]
}

# ===================
# Python言語固有関数テスト
# ===================

@test "_fix_lint_python uses autopep8 when available" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/autopep8" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "autopep8 executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/autopep8"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_lint_python
    [ "$status" -eq 0 ]
    [[ "$output" == *"autopep8"* ]]
}

@test "_fix_lint_python returns 1 when autopep8 fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/autopep8" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/autopep8"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_lint_python
    [ "$status" -eq 1 ]
}

@test "_fix_lint_python returns 2 when autopep8 not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-autopep8"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-autopep8/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-autopep8"

    run _fix_lint_python
    export PATH="$saved_path"
    [ "$status" -eq 2 ]
    [[ "$output" == *"autopep8 not found"* ]]
}

@test "_fix_format_python uses black when available" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/black" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "black executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/black"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_python
    [ "$status" -eq 0 ]
    [[ "$output" == *"black"* ]]
}

@test "_fix_format_python returns 1 when black fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/black" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/black"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_python
    [ "$status" -eq 1 ]
}

@test "_fix_format_python falls back to autopep8 when black not found" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    # No black mock, but provide autopep8
    cat > "$BATS_TEST_TMPDIR/mocks/autopep8" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "autopep8 executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/autopep8"
    # Ensure no black in this mock dir, use restricted PATH
    mkdir -p "$BATS_TEST_TMPDIR/no-black"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-black/$cmd"
    done
    ln -sf "$BATS_TEST_TMPDIR/mocks/autopep8" "$BATS_TEST_TMPDIR/no-black/autopep8"
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-black"

    run _fix_format_python
    export PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"autopep8"* ]]
}

@test "_fix_format_python returns 2 when no formatter found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-py-fmt"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-py-fmt/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-py-fmt"

    run _fix_format_python
    export PATH="$saved_path"
    [ "$status" -eq 2 ]
    [[ "$output" == *"No formatter found"* ]]
}

@test "_validate_python runs flake8 and pytest" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/flake8" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "flake8 OK"
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/pytest" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "pytest OK"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/flake8" "$BATS_TEST_TMPDIR/mocks/pytest"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_python
    [ "$status" -eq 0 ]
}

@test "_validate_python returns 1 when flake8 fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/flake8" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "E501 line too long" >&2
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/flake8"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_python
    [ "$status" -eq 1 ]
}

@test "_validate_python returns 1 when pytest fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/flake8" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/pytest" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "FAILED"
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/flake8" "$BATS_TEST_TMPDIR/mocks/pytest"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_python
    [ "$status" -eq 1 ]
}

# ===================
# Rust言語固有関数テスト
# ===================

@test "_fix_lint_rust uses cargo clippy --fix" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "cargo $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_lint_rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"Clippy fix applied"* ]]
}

@test "_fix_lint_rust returns 1 when cargo clippy --fix fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_lint_rust
    [ "$status" -eq 1 ]
}

@test "_fix_lint_rust returns 1 when cargo not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-cargo"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-cargo/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-cargo"

    run _fix_lint_rust
    export PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cargo not found"* ]]
}

@test "_fix_format_rust uses cargo fmt" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "cargo $* executed"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"Format fix applied"* ]]
}

@test "_fix_format_rust returns 1 when cargo fmt fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _fix_format_rust
    [ "$status" -eq 1 ]
}

@test "_fix_format_rust returns 1 when cargo not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-cargo2"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-cargo2/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-cargo2"

    run _fix_format_rust
    export PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cargo not found"* ]]
}

@test "_validate_rust runs clippy and tests" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "cargo $* OK"
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_rust
    [ "$status" -eq 0 ]
}

@test "_validate_rust returns 1 when clippy fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "clippy" ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_rust
    [ "$status" -eq 1 ]
}

@test "_validate_rust returns 1 when cargo test fails" {
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/cargo" << 'MOCK_EOF'
#!/usr/bin/env bash
if [[ "$1" == "test" ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/cargo"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run _validate_rust
    [ "$status" -eq 1 ]
}

@test "_validate_rust skips when cargo not found" {
    mkdir -p "$BATS_TEST_TMPDIR/no-cargo3"
    for cmd in bash cat grep sed awk; do
        local cmd_path
        cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
        [[ -n "$cmd_path" ]] && ln -sf "$cmd_path" "$BATS_TEST_TMPDIR/no-cargo3/$cmd"
    done
    local saved_path="$PATH"
    export PATH="$BATS_TEST_TMPDIR/no-cargo3"

    run _validate_rust
    export PATH="$saved_path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cargo not found"* ]]
}

# ===================
# run_local_validation with mocked commands
# ===================

@test "run_local_validation dispatches to correct language validator" {
    # Create a bash project
    mkdir -p "$BATS_TEST_TMPDIR/rlv-bash/scripts" "$BATS_TEST_TMPDIR/rlv-bash/lib"
    touch "$BATS_TEST_TMPDIR/rlv-bash/test.bats"
    touch "$BATS_TEST_TMPDIR/rlv-bash/scripts/run.sh" "$BATS_TEST_TMPDIR/rlv-bash/lib/log.sh"
    
    mkdir -p "$BATS_TEST_TMPDIR/mocks"
    cat > "$BATS_TEST_TMPDIR/mocks/shellcheck" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    cat > "$BATS_TEST_TMPDIR/mocks/bats" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mocks/shellcheck" "$BATS_TEST_TMPDIR/mocks/bats"
    export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

    run run_local_validation "$BATS_TEST_TMPDIR/rlv-bash"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bash"* ]]
}
