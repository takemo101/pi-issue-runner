#!/usr/bin/env bats
# cleanup-orphans.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeディレクトリを設定
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    source "$PROJECT_ROOT/lib/cleanup-orphans.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # ログを抑制
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# cleanup_orphaned_statuses dry_run=true テスト
# ====================

@test "cleanup_orphaned_statuses dry_run=true does not delete files" {
    # 孤立したステータスファイルを作成
    save_status "100" "complete" "pi-issue-100"
    
    # dry_run=true で実行
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    
    # ファイルがまだ存在することを確認
    [ -f "$TEST_WORKTREE_DIR/.status/100.json" ]
}

@test "cleanup_orphaned_statuses dry_run=true shows DRY-RUN message" {
    # 孤立したステータスファイルを作成
    save_status "101" "complete" "pi-issue-101"
    
    # dry_run=true で実行
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
}

@test "cleanup_orphaned_statuses dry_run=true shows issue number" {
    # 孤立したステータスファイルを作成
    save_status "102" "complete" "pi-issue-102"
    
    # dry_run=true で実行
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"102"* ]]
}

# ====================
# cleanup_orphaned_statuses dry_run=false テスト
# ====================

@test "cleanup_orphaned_statuses dry_run=false deletes orphaned files" {
    # 孤立したステータスファイルを作成
    save_status "200" "complete" "pi-issue-200"
    
    # ファイルが存在することを確認
    [ -f "$TEST_WORKTREE_DIR/.status/200.json" ]
    
    # dry_run=false で実行
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # ファイルが削除されていることを確認
    [ ! -f "$TEST_WORKTREE_DIR/.status/200.json" ]
}

@test "cleanup_orphaned_statuses dry_run=false shows removed message" {
    # 孤立したステータスファイルを作成
    save_status "201" "complete" "pi-issue-201"
    
    # dry_run=false で実行
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removing"* ]] || [[ "$output" == *"Removed"* ]]
}

@test "cleanup_orphaned_statuses deletes multiple orphaned files" {
    # 複数の孤立したステータスファイルを作成
    save_status "202" "complete" "pi-issue-202"
    save_status "203" "error" "pi-issue-203"
    save_status "204" "running" "pi-issue-204"
    
    # dry_run=false で実行
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # 全てのファイルが削除されていることを確認
    [ ! -f "$TEST_WORKTREE_DIR/.status/202.json" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/203.json" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/204.json" ]
}

# ====================
# 孤立ステータスなしの場合
# ====================

@test "cleanup_orphaned_statuses with no orphans shows appropriate message" {
    init_status_dir
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No orphaned status files found"* ]]
}

@test "cleanup_orphaned_statuses preserves non-orphaned status files" {
    # worktreeディレクトリを作成
    mkdir -p "$TEST_WORKTREE_DIR/issue-300-test"
    
    # 対応するステータスファイルを作成
    save_status "300" "running" "pi-issue-300"
    
    # dry_run=false で実行
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # worktreeがあるのでファイルは保持される
    [ -f "$TEST_WORKTREE_DIR/.status/300.json" ]
}

@test "cleanup_orphaned_statuses handles mixed cases correctly" {
    # worktreeがあるものとないものを作成
    mkdir -p "$TEST_WORKTREE_DIR/issue-400-with-worktree"
    
    save_status "400" "running" "pi-issue-400"  # worktreeあり
    save_status "401" "complete" "pi-issue-401"  # worktreeなし
    
    # dry_run=false で実行
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # 400は保持、401は削除
    [ -f "$TEST_WORKTREE_DIR/.status/400.json" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/401.json" ]
}

# ====================
# age_days パラメータテスト
# ====================

@test "cleanup_orphaned_statuses with age_days ignores recent files" {
    # 孤立した新しいステータスファイルを作成
    save_status "500" "complete" "pi-issue-500"
    
    # 7日より古いファイルのみ対象
    run cleanup_orphaned_statuses "false" "7"
    [ "$status" -eq 0 ]
    
    # 新しいファイルは削除されない
    [ -f "$TEST_WORKTREE_DIR/.status/500.json" ]
}

@test "cleanup_orphaned_statuses with age_days shows appropriate message" {
    init_status_dir
    
    run cleanup_orphaned_statuses "true" "30"
    [ "$status" -eq 0 ]
    [[ "$output" == *"30 days"* ]]
}

@test "cleanup_orphaned_statuses with age_days deletes old files" {
    # 孤立したステータスファイルを作成して古い日付に設定
    save_status "501" "complete" "pi-issue-501"
    touch -t 202001010000 "$TEST_WORKTREE_DIR/.status/501.json"
    
    # 1日より古いファイルを削除
    run cleanup_orphaned_statuses "false" "1"
    [ "$status" -eq 0 ]
    
    # 古いファイルは削除される
    [ ! -f "$TEST_WORKTREE_DIR/.status/501.json" ]
}

@test "cleanup_orphaned_statuses with age_days preserves recent orphaned files" {
    # 古いファイルと新しいファイルを作成
    save_status "502" "complete" "pi-issue-502"
    touch -t 202001010000 "$TEST_WORKTREE_DIR/.status/502.json"
    
    save_status "503" "complete" "pi-issue-503"
    # 503は新しいファイル（今作成した）
    
    # 1日より古いファイルのみ削除
    run cleanup_orphaned_statuses "false" "1"
    [ "$status" -eq 0 ]
    
    # 古いファイルは削除、新しいファイルは保持
    [ ! -f "$TEST_WORKTREE_DIR/.status/502.json" ]
    [ -f "$TEST_WORKTREE_DIR/.status/503.json" ]
}

# ====================
# デフォルト引数テスト
# ====================

@test "cleanup_orphaned_statuses defaults to dry_run=false" {
    # 孤立したステータスファイルを作成
    save_status "600" "complete" "pi-issue-600"
    
    # 引数なしで実行（デフォルト: dry_run=false）
    run cleanup_orphaned_statuses
    [ "$status" -eq 0 ]
    
    # ファイルが削除されていることを確認
    [ ! -f "$TEST_WORKTREE_DIR/.status/600.json" ]
}

# ====================
# エッジケーステスト
# ====================

@test "cleanup_orphaned_statuses handles empty status directory" {
    # ステータスディレクトリは存在するがファイルなし
    init_status_dir
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No orphaned status files found"* ]]
}

@test "cleanup_orphaned_statuses handles status directory not existing" {
    # ステータスディレクトリを削除
    rm -rf "$TEST_WORKTREE_DIR/.status"
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
}

@test "cleanup_orphaned_statuses dry_run=true shows count of orphaned files" {
    # 複数の孤立したステータスファイルを作成
    save_status "700" "complete" "pi-issue-700"
    save_status "701" "complete" "pi-issue-701"
    save_status "702" "complete" "pi-issue-702"
    
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
}
