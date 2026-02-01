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
