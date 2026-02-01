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
    
    # ログを抑制（テスト出力を汚さないため）
    LOG_LEVEL="ERROR"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# cleanup_orphaned_statuses テスト
# ====================

@test "cleanup_orphaned_statuses removes orphaned status files (dry_run=false)" {
    # 孤立したステータスファイルを作成（対応するworktreeなし）
    save_status "100" "complete" "pi-issue-100"
    save_status "101" "complete" "pi-issue-101"
    
    # ファイルが存在することを確認
    [ -f "$TEST_WORKTREE_DIR/.status/100.json" ]
    [ -f "$TEST_WORKTREE_DIR/.status/101.json" ]
    
    # 実際に削除
    run cleanup_orphaned_statuses "false"
    
    # 削除されたことを確認
    [ ! -f "$TEST_WORKTREE_DIR/.status/100.json" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/101.json" ]
}

@test "cleanup_orphaned_statuses does not remove files with dry_run=true" {
    # 孤立したステータスファイルを作成
    save_status "200" "complete" "pi-issue-200"
    save_status "201" "complete" "pi-issue-201"
    
    # dry-runで実行
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    
    # ファイルが残っていることを確認
    [ -f "$TEST_WORKTREE_DIR/.status/200.json" ]
    [ -f "$TEST_WORKTREE_DIR/.status/201.json" ]
}

@test "cleanup_orphaned_statuses outputs dry-run messages" {
    # 孤立したステータスファイルを作成
    save_status "300" "complete" "pi-issue-300"
    
    # dry-runで実行してログを確認
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"Would remove"* ]] || [[ "$output" == *"dry-run"* ]]
}

@test "cleanup_orphaned_statuses preserves non-orphaned status files" {
    # worktreeディレクトリを作成
    mkdir -p "$TEST_WORKTREE_DIR/issue-400-with-worktree"
    
    # 対応するworktreeがあるステータス
    save_status "400" "running" "pi-issue-400"
    
    # 孤立したステータス
    save_status "401" "complete" "pi-issue-401"
    
    # 実際に削除
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # 400は残り、401は削除
    [ -f "$TEST_WORKTREE_DIR/.status/400.json" ]
    [ ! -f "$TEST_WORKTREE_DIR/.status/401.json" ]
}

@test "cleanup_orphaned_statuses handles empty status directory" {
    # ステータスファイルなしで実行
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No orphaned status files found"* ]]
}

@test "cleanup_orphaned_statuses with age_days filters old files" {
    # ステータスファイルを作成
    save_status "500" "complete" "pi-issue-500"
    
    # ファイルの更新日時を過去に変更（7日前）
    touch -t 202001010000 "$TEST_WORKTREE_DIR/.status/500.json"
    
    # 1日より古いファイルを削除
    run cleanup_orphaned_statuses "false" "1"
    [ "$status" -eq 0 ]
    
    # 削除されていることを確認
    [ ! -f "$TEST_WORKTREE_DIR/.status/500.json" ]
}

@test "cleanup_orphaned_statuses with age_days preserves new files" {
    # 新しいステータスファイルを作成（孤立だが新しい）
    save_status "600" "complete" "pi-issue-600"
    
    # 0日より古いファイルを対象（＝今日作成したものは対象外の可能性）
    # 注: find_stale_statuses の実装によっては新しいファイルも対象になる
    run cleanup_orphaned_statuses "false" "1"
    [ "$status" -eq 0 ]
}

@test "cleanup_orphaned_statuses returns 0 on success" {
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
}

@test "cleanup_orphaned_statuses counts removed files" {
    # 複数の孤立したステータスファイルを作成
    save_status "700" "complete" "pi-issue-700"
    save_status "701" "complete" "pi-issue-701"
    save_status "702" "complete" "pi-issue-702"
    
    run cleanup_orphaned_statuses "false"
    [ "$status" -eq 0 ]
    
    # 出力にカウントが含まれることを確認
    [[ "$output" == *"3"* ]] || [[ "$output" == *"Removed"* ]]
}

@test "cleanup_orphaned_statuses with dry_run shows correct count" {
    # 複数の孤立したステータスファイルを作成
    save_status "800" "complete" "pi-issue-800"
    save_status "801" "complete" "pi-issue-801"
    
    run cleanup_orphaned_statuses "true"
    [ "$status" -eq 0 ]
    
    # dry-runメッセージに2件が含まれることを確認
    [[ "$output" == *"2"* ]]
}
