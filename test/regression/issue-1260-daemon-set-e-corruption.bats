#!/usr/bin/env bats
# test/regression/issue-1260-daemon-set-e-corruption.bats
# 回帰テスト: daemon.sh の is_daemon_running/stop_daemon が
# set +e/set -e パターンで呼び出し元のエラー処理を破壊する問題

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        BATS_TEST_TMPDIR="$(mktemp -d)"
        export BATS_TEST_TMPDIR
    fi
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "Issue #1260: is_daemon_running does not corrupt set -e in if context" {
    # set -e コンテキストの if 文で呼んだ場合に
    # スクリプトが予期せず終了しないことを確認
    run bash -c '
        set -euo pipefail
        source "'"$PROJECT_ROOT"'/lib/daemon.sh"
        if is_daemon_running 99999; then
            echo "running"
        else
            echo "not running"
        fi
        echo "script continued"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"not running"* ]]
    [[ "$output" == *"script continued"* ]]
}

@test "Issue #1260: stop_daemon does not corrupt set -e in if context" {
    run bash -c '
        set -euo pipefail
        source "'"$PROJECT_ROOT"'/lib/daemon.sh"
        if stop_daemon 99999; then
            echo "stopped"
        else
            echo "not stopped"
        fi
        echo "script continued"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"not stopped"* ]]
    [[ "$output" == *"script continued"* ]]
}

@test "Issue #1260: is_daemon_running preserves caller set +e state" {
    # 呼び出し元が set +e の場合、関数呼び出し後も set +e のままであること
    run bash -c '
        set -euo pipefail
        source "'"$PROJECT_ROOT"'/lib/daemon.sh"
        set +e
        is_daemon_running 99999
        # set +e が維持されているか確認（false がスクリプトを終了させないはず）
        false
        echo "set +e preserved"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"set +e preserved"* ]]
}

@test "Issue #1260: stop_daemon preserves caller set +e state" {
    run bash -c '
        set -euo pipefail
        source "'"$PROJECT_ROOT"'/lib/daemon.sh"
        set +e
        stop_daemon 99999
        false
        echo "set +e preserved"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"set +e preserved"* ]]
}

@test "Issue #1260: daemon functions do not contain set +e/set -e pattern" {
    # ソースコード中に set +e / set -e パターンが存在しないことを確認
    source "$PROJECT_ROOT/lib/daemon.sh"
    
    # is_daemon_running と stop_daemon の関数定義を取得
    local func_body
    func_body=$(declare -f is_daemon_running stop_daemon)
    
    # set +e / set -e パターンが含まれていないことを確認
    ! echo "$func_body" | grep -q 'set +e'
    ! echo "$func_body" | grep -q 'set -e'
}
