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
    
    # status.shを先に読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/status.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            *) echo "" ;;
        esac
    }
    
    # cleanup-orphans.shを読み込み
    source "$PROJECT_ROOT/lib/cleanup-orphans.sh"
    
    # ログを抑制
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# cleanup_orphaned_statuses テスト（孤立ファイルなし）
# ====================

@test "cleanup_orphaned_statuses returns 0 with no orphaned files" {
    # ステータスファイルなし
    init_status_dir
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No orphaned status files found"* ]]
}

@test "cleanup_orphaned_statuses handles empty status directory" {
    init_status_dir
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
}

# ====================
# cleanup_orphaned_statuses テスト（孤立ファイルあり）
# ====================

@test "cleanup_orphaned_statuses removes orphaned status files" {
    # 孤立したステータスファイルを作成（対応するworktreeなし）
    save_status "100" "complete" "pi-issue-100"
    save_status "101" "error" "pi-issue-101"
    
    # ファイルが存在することを確認
    [ -f "$TEST_WORKTREE_DIR/.status/100.json" ]
    [ -f "$TEST_WORKTREE_DIR/.status/101.json" ]
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # 孤立ファイルが削除されたことを確認
    [ ! -f "$TEST_WORKTREE_DIR/.status/100.json" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/101.json" ]
}

@test "cleanup_orphaned_statuses reports count of removed files" {
    save_status "200" "complete" "pi-issue-200"
    save_status "201" "complete" "pi-issue-201"
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed 2 orphaned status file(s)"* ]]
}

@test "cleanup_orphaned_statuses preserves files with worktree" {
    # worktreeディレクトリを作成
    mkdir -p "$TEST_WORKTREE_DIR/issue-300-with-worktree"
    
    # 対応するworktreeがあるステータスファイル
    save_status "300" "running" "pi-issue-300"
    
    # 孤立したステータスファイル（worktreeなし）
    save_status "301" "complete" "pi-issue-301"
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # worktreeがあるファイルは保持
    [ -f "$TEST_WORKTREE_DIR/.status/300.json" ]
    # 孤立ファイルは削除
    [ ! -f "$TEST_WORKTREE_DIR/.status/301.json" ]
}

# ====================
# cleanup_orphaned_statuses dry-run テスト
# ====================

@test "cleanup_orphaned_statuses dry-run does not delete files" {
    save_status "400" "complete" "pi-issue-400"
    
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    
    # dry-runなのでファイルは残っている
    [ -f "$TEST_WORKTREE_DIR/.status/400.json" ]
}

@test "cleanup_orphaned_statuses dry-run outputs DRY-RUN message" {
    save_status "401" "complete" "pi-issue-401"
    
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "cleanup_orphaned_statuses dry-run reports would-remove count" {
    save_status "402" "complete" "pi-issue-402"
    save_status "403" "complete" "pi-issue-403"
    
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would remove"* ]] || [[ "$output" == *"Would remove 2 orphaned status file(s)"* ]]
}

# ====================
# cleanup_orphaned_statuses age_days テスト
# ====================

@test "cleanup_orphaned_statuses with age_days filters new files" {
    # 新しいステータスファイルを作成
    save_status "500" "complete" "pi-issue-500"
    
    # 7日より古いファイルを対象（新しいファイルは対象外）
    run cleanup_orphaned_statuses "false" "7"
    [ "$status" -eq 0 ]
    
    # 新しいファイルは削除されない
    [ -f "$TEST_WORKTREE_DIR/.status/500.json" ]
}

@test "cleanup_orphaned_statuses with age_days removes old files" {
    # 古いステータスファイルを作成
    save_status "501" "complete" "pi-issue-501"
    # ファイルのタイムスタンプを過去に変更（2020年1月1日）
    touch -t 202001010000 "$TEST_WORKTREE_DIR/.status/501.json"
    
    # 1日より古いファイルを対象
    run cleanup_orphaned_statuses "false" "1"
    [ "$status" -eq 0 ]
    
    # 古いファイルは削除される
    [ ! -f "$TEST_WORKTREE_DIR/.status/501.json" ]
}

@test "cleanup_orphaned_statuses with age_days shows appropriate message" {
    init_status_dir
    
    run cleanup_orphaned_statuses "false" "30"
    [ "$status" -eq 0 ]
    [[ "$output" == *"older than 30 days"* ]] || [[ "$output" == *"No orphaned status files"* ]]
}

@test "cleanup_orphaned_statuses with age_days dry-run preserves files" {
    save_status "502" "complete" "pi-issue-502"
    touch -t 202001010000 "$TEST_WORKTREE_DIR/.status/502.json"
    
    run cleanup_orphaned_statuses "true" "1"
    [ "$status" -eq 0 ]
    
    # dry-runなのでファイルは残っている
    [ -f "$TEST_WORKTREE_DIR/.status/502.json" ]
}

# ====================
# エッジケーステスト
# ====================

@test "cleanup_orphaned_statuses handles default parameters" {
    save_status "600" "complete" "pi-issue-600"
    
    # パラメータなし（デフォルト: dry_run=false, age_days未指定）
    run cleanup_orphaned_statuses
    [ "$status" -eq 0 ]
    
    # 孤立ファイルは削除される
    [ ! -f "$TEST_WORKTREE_DIR/.status/600.json" ]
}

@test "cleanup_orphaned_statuses handles single orphan" {
    save_status "700" "complete" "pi-issue-700"
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed 1 orphaned status file(s)"* ]]
}
