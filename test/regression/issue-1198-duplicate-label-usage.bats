#!/usr/bin/env bats
# test/regression/issue-1198-duplicate-label-usage.bats
# 回帰テスト: run.sh の usage() で -l, --label オプションが重複定義されていないことを確認

load '../test_helper'

@test "regression #1198: -l, --label appears exactly once in help output" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]

    local count
    count=$(echo "$output" | grep -c '\-l, --label' || true)
    [ "$count" -eq 1 ]
}
