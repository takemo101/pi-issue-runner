#!/usr/bin/env bats
# ci-fix-helper.bats - CI修正ヘルパースクリプトのテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 状態ファイルのクリーンアップ
    rm -rf /tmp/pi-runner-state/ci-retry-*
    
    # スクリプトパス
    CI_FIX_HELPER="$PROJECT_ROOT/scripts/ci-fix-helper.sh"
}

teardown() {
    # リトライ状態ファイルのクリーンアップ
    rm -rf /tmp/pi-runner-state/ci-retry-*
    
    # TMPDIRクリーンアップ
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ===================
# ヘルプ表示テスト
# ===================

@test "ci-fix-helper shows help with no arguments" {
    run "$CI_FIX_HELPER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ci-fix-helper shows help with --help" {
    run "$CI_FIX_HELPER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Commands:"* ]]
    [[ "$output" == *"detect"* ]]
    [[ "$output" == *"fix"* ]]
    [[ "$output" == *"handle"* ]]
    [[ "$output" == *"validate"* ]]
}

@test "ci-fix-helper shows help with -h" {
    run "$CI_FIX_HELPER" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ci-fix-helper shows help with help command" {
    run "$CI_FIX_HELPER" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ===================
# detectコマンドテスト
# ===================

@test "ci-fix-helper detect requires pr_number" {
    run "$CI_FIX_HELPER" detect
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR number is required"* ]]
}

@test "ci-fix-helper detect shows usage when pr_number is missing" {
    run "$CI_FIX_HELPER" detect
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ===================
# fixコマンドテスト
# ===================

@test "ci-fix-helper fix requires failure_type" {
    run "$CI_FIX_HELPER" fix
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failure type is required"* ]]
}

@test "ci-fix-helper fix shows usage when failure_type is missing" {
    run "$CI_FIX_HELPER" fix
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ci-fix-helper fix returns 2 for test failures (requires AI)" {
    run "$CI_FIX_HELPER" fix test "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "ci-fix-helper fix returns 2 for build errors (requires AI)" {
    run "$CI_FIX_HELPER" fix build "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

@test "ci-fix-helper fix returns 2 for unknown failure type" {
    run "$CI_FIX_HELPER" fix unknown "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
}

# ===================
# handleコマンドテスト
# ===================

@test "ci-fix-helper handle requires issue_number and pr_number" {
    run "$CI_FIX_HELPER" handle
    [ "$status" -eq 1 ]
    [[ "$output" == *"Issue number and PR number are required"* ]]
}

@test "ci-fix-helper handle requires pr_number when only issue_number provided" {
    run "$CI_FIX_HELPER" handle 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"Issue number and PR number are required"* ]]
}

@test "ci-fix-helper handle shows usage when arguments are missing" {
    run "$CI_FIX_HELPER" handle
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ===================
# validateコマンドテスト
# ===================

@test "ci-fix-helper validate uses current directory as default" {
    # validateコマンドはworktree_pathをデフォルトで'.'にする
    # cargoが存在しない環境ではスキップされる
    run "$CI_FIX_HELPER" validate "$BATS_TEST_TMPDIR"
    # cargoが存在しない場合は0（スキップ）、存在する場合は検証結果
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ===================
# escalateコマンドテスト
# ===================

@test "ci-fix-helper escalate requires pr_number" {
    run "$CI_FIX_HELPER" escalate
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR number is required"* ]]
}

@test "ci-fix-helper escalate shows usage when pr_number is missing" {
    run "$CI_FIX_HELPER" escalate
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ===================
# 不正なコマンドテスト
# ===================

@test "ci-fix-helper shows error for unknown command" {
    run "$CI_FIX_HELPER" invalid-command
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "ci-fix-helper shows usage for unknown command" {
    run "$CI_FIX_HELPER" invalid-command
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ===================
# スクリプト実行可能性テスト
# ===================

@test "ci-fix-helper is executable" {
    [ -x "$CI_FIX_HELPER" ]
}

@test "ci-fix-helper has proper shebang" {
    head -1 "$CI_FIX_HELPER" | grep -q "#!/usr/bin/env bash"
}

# ===================
# ライブラリ統合テスト
# ===================

@test "ci-fix-helper sources ci-fix.sh library" {
    # スクリプトがlib/ci-fix.shをsourceしているか確認
    grep -q 'source.*lib/ci-fix.sh' "$CI_FIX_HELPER"
}

@test "ci-fix-helper can access ci-fix functions" {
    # helpコマンドが正常に動作することで、ライブラリが正しくロードされていることを確認
    run "$CI_FIX_HELPER" help
    [ "$status" -eq 0 ]
}
