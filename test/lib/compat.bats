#!/usr/bin/env bats
# test/lib/compat.bats - compat.sh のユニットテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    source "$PROJECT_ROOT/lib/compat.sh"
}

@test "safe_timeout is defined" {
    declare -f safe_timeout
}

@test "safe_timeout runs command successfully" {
    run safe_timeout 10 echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "safe_timeout passes arguments correctly" {
    run safe_timeout 10 printf "%s-%s" foo bar
    [ "$status" -eq 0 ]
    [ "$output" = "foo-bar" ]
}

@test "safe_timeout propagates command failure exit code" {
    run safe_timeout 10 false
    [ "$status" -ne 0 ]
}

@test "safe_timeout works when timeout command is not available" {
    # timeout コマンドを隠す
    timeout() { :; }
    unset -f timeout
    # PATHからtimeoutを除外
    local orig_path="$PATH"
    PATH="/usr/bin:/bin"
    # command -v timeout が失敗する環境でもコマンドが実行される
    # compat.sh を再読み込み（ソースガードをリセット）
    unset _COMPAT_SH_SOURCED
    source "$PROJECT_ROOT/lib/compat.sh"
    run safe_timeout 10 echo "no-timeout-ok"
    PATH="$orig_path"
    [ "$status" -eq 0 ]
    [ "$output" = "no-timeout-ok" ]
}

@test "safe_timeout requires seconds argument" {
    # 引数なしだと shift で失敗する
    run safe_timeout
    [ "$status" -ne 0 ]
}

@test "compat.sh source guard prevents double loading" {
    # 既に loaded なので再source しても問題ない
    source "$PROJECT_ROOT/lib/compat.sh"
    declare -f safe_timeout
}
