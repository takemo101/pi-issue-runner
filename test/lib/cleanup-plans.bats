#!/usr/bin/env bats
# cleanup-plans.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # テスト用ディレクトリを設定
    export TEST_PLANS_DIR="$BATS_TEST_TMPDIR/docs/plans"
    mkdir -p "$TEST_PLANS_DIR"
    
    # cleanup_closed_issue_plans用のプロジェクトディレクトリ（docs/plansを使用）
    export TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT_DIR/docs/plans"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    
    # load_config/get_config をオーバーライド
    load_config() { :; }
    get_config() {
        case "$1" in
            plans_dir) echo "$TEST_PLANS_DIR" ;;
            plans_keep_recent) echo "3" ;;
            *) echo "" ;;
        esac
    }
    
    source "$PROJECT_ROOT/lib/cleanup-plans.sh"
    
    # ログを抑制
    LOG_LEVEL="ERROR"
}

teardown() {
    # PATHを復元
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ghコマンドのモック（Issue状態を返す）
# gh issue view $num --json state -q '.state' の形式で呼ばれる
mock_gh_for_issues() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
# Issue番号をパースして状態を返す
# gh issue view $num --json state -q '.state' 形式で呼ばれる
case "$*" in
    *"issue view 100"*"--json state"*"-q"*)
        echo 'CLOSED'
        ;;
    *"issue view 101"*"--json state"*"-q"*)
        echo 'OPEN'
        ;;
    *"issue view 102"*"--json state"*"-q"*)
        echo 'CLOSED'
        ;;
    *"issue view 999"*"--json state"*"-q"*)
        echo "issue not found" >&2
        exit 1
        ;;
    *)
        # デフォルトはOPEN
        echo 'OPEN'
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# ====================
# cleanup_old_plans テスト
# ====================

@test "cleanup_old_plans keeps recent plans based on keep_count" {
    # 5つの計画書を作成
    for i in 1 2 3 4 5; do
        echo "Plan $i" > "$TEST_PLANS_DIR/issue-${i}-plan.md"
        # ファイルの更新日時をずらす（1が最古）
        touch -t "2024010${i}0000" "$TEST_PLANS_DIR/issue-${i}-plan.md"
    done
    
    # keep_count=3 で削除
    run cleanup_old_plans "false" "3"
    [ "$status" -eq 0 ]
    
    # 古い2つ（issue-1, issue-2）が削除され、新しい3つが残る
    [ ! -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ ! -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-4-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-5-plan.md" ]
}

@test "cleanup_old_plans with dry_run does not delete files" {
    # 5つの計画書を作成
    for i in 1 2 3 4 5; do
        echo "Plan $i" > "$TEST_PLANS_DIR/issue-${i}-plan.md"
        touch -t "2024010${i}0000" "$TEST_PLANS_DIR/issue-${i}-plan.md"
    done
    
    # dry_run=true で実行
    run cleanup_old_plans "true" "3"
    [ "$status" -eq 0 ]
    
    # 全てのファイルが残っていることを確認
    [ -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-4-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-5-plan.md" ]
}

@test "cleanup_old_plans outputs dry-run messages" {
    # 計画書を作成
    for i in 1 2 3 4 5; do
        echo "Plan $i" > "$TEST_PLANS_DIR/issue-${i}-plan.md"
        touch -t "2024010${i}0000" "$TEST_PLANS_DIR/issue-${i}-plan.md"
    done
    
    run cleanup_old_plans "true" "3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
}

@test "cleanup_old_plans with keep_count=0 keeps all files" {
    # 計画書を作成
    for i in 1 2 3; do
        echo "Plan $i" > "$TEST_PLANS_DIR/issue-${i}-plan.md"
    done
    
    # keep_count=0 は全て保持
    run cleanup_old_plans "false" "0"
    [ "$status" -eq 0 ]
    
    # 全てのファイルが残っていることを確認
    [ -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
}

@test "cleanup_old_plans handles empty plans directory" {
    run cleanup_old_plans "false" "3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files found"* ]]
}

@test "cleanup_old_plans handles non-existent plans directory" {
    # plans_dirを存在しないディレクトリに変更
    get_config() {
        case "$1" in
            plans_dir) echo "$BATS_TEST_TMPDIR/nonexistent" ;;
            plans_keep_recent) echo "3" ;;
            *) echo "" ;;
        esac
    }
    
    run cleanup_old_plans "false" "3"
    [ "$status" -eq 0 ]
}

@test "cleanup_old_plans keeps all when count is less than or equal to keep_count" {
    # 2つの計画書を作成（keep_count=3より少ない）
    echo "Plan 1" > "$TEST_PLANS_DIR/issue-1-plan.md"
    echo "Plan 2" > "$TEST_PLANS_DIR/issue-2-plan.md"
    
    run cleanup_old_plans "false" "3"
    [ "$status" -eq 0 ]
    
    # 全て保持されていることを確認
    [ -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
}

@test "cleanup_old_plans uses config when keep_count not specified" {
    # 5つの計画書を作成
    for i in 1 2 3 4 5; do
        echo "Plan $i" > "$TEST_PLANS_DIR/issue-${i}-plan.md"
        touch -t "2024010${i}0000" "$TEST_PLANS_DIR/issue-${i}-plan.md"
    done
    
    # keep_countを指定しない（configから取得 = 3）
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
    
    # 古い2つが削除されていることを確認
    [ ! -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ ! -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
}

# ====================
# cleanup_closed_issue_plans テスト
# ====================

@test "cleanup_closed_issue_plans removes closed issue plans" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    
    # プロジェクトディレクトリに移動（docs/plansがハードコードされているため）
    cd "$TEST_PROJECT_DIR"
    
    # Issue #100 (CLOSED) と #101 (OPEN) の計画書を作成
    echo "Plan for issue 100" > "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md"
    echo "Plan for issue 101" > "$TEST_PROJECT_DIR/docs/plans/issue-101-plan.md"
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # #100は削除、#101は保持
    [ ! -f "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md" ]
    [ -f "$TEST_PROJECT_DIR/docs/plans/issue-101-plan.md" ]
}

@test "cleanup_closed_issue_plans with dry_run does not delete" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    echo "Plan for issue 100" > "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md"
    
    run cleanup_closed_issue_plans "true"
    [ "$status" -eq 0 ]
    
    # ファイルが残っていることを確認
    [ -f "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md" ]
}

@test "cleanup_closed_issue_plans outputs dry-run messages" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    echo "Plan for issue 100" > "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md"
    
    run cleanup_closed_issue_plans "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
}

@test "cleanup_closed_issue_plans handles multiple closed issues" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    # 複数のCLOSED Issue計画書を作成
    echo "Plan for issue 100" > "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md"
    echo "Plan for issue 102" > "$TEST_PROJECT_DIR/docs/plans/issue-102-plan.md"
    echo "Plan for issue 101" > "$TEST_PROJECT_DIR/docs/plans/issue-101-plan.md"  # OPEN
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # CLOSED は削除、OPEN は保持
    [ ! -f "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md" ]
    [ ! -f "$TEST_PROJECT_DIR/docs/plans/issue-102-plan.md" ]
    [ -f "$TEST_PROJECT_DIR/docs/plans/issue-101-plan.md" ]
}

@test "cleanup_closed_issue_plans handles empty plans directory" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files found"* ]]
}

@test "cleanup_closed_issue_plans handles non-existent plans directory" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    
    # プロジェクトディレクトリでdocs/plansを削除
    cd "$TEST_PROJECT_DIR"
    rm -rf "$TEST_PROJECT_DIR/docs/plans"
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plans directory found"* ]]
}

@test "cleanup_closed_issue_plans handles gh CLI errors gracefully" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    # Issue #999 は存在しない（モックでエラーを返す）
    echo "Plan for issue 999" > "$TEST_PROJECT_DIR/docs/plans/issue-999-plan.md"
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # エラーの場合は削除しない（UNKNOWN扱い）
    [ -f "$TEST_PROJECT_DIR/docs/plans/issue-999-plan.md" ]
}

@test "cleanup_closed_issue_plans reports count of deleted files" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    echo "Plan for issue 100" > "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md"
    echo "Plan for issue 102" > "$TEST_PROJECT_DIR/docs/plans/issue-102-plan.md"
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # 出力に削除件数が含まれることを確認
    [[ "$output" == *"2"* ]] || [[ "$output" == *"Deleted"* ]]
}

@test "cleanup_closed_issue_plans without gh CLI returns error" {
    cd "$TEST_PROJECT_DIR"
    
    # 事前にディレクトリとファイルを準備
    mkdir -p "$BATS_TEST_TMPDIR/empty"
    echo "Plan for issue 100" > "$TEST_PROJECT_DIR/docs/plans/issue-100-plan.md"
    
    # ghコマンドをPATHから除外（空のディレクトリのみのPATHに）
    # 注: bashビルトインコマンド以外は使用不可になる
    export PATH="$BATS_TEST_TMPDIR/empty"
    
    run cleanup_closed_issue_plans "false"
    # ghがない場合はエラー
    [ "$status" -eq 1 ] || [[ "$output" == *"gh"* ]]
}

@test "cleanup_closed_issue_plans reports no files to delete when all open" {
    mock_gh_for_issues
    export PATH="$MOCK_DIR:$PATH"
    cd "$TEST_PROJECT_DIR"
    
    echo "Plan for issue 101" > "$TEST_PROJECT_DIR/docs/plans/issue-101-plan.md"  # OPEN
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No closed issue plans found"* ]] || [[ "$output" == *"0"* ]]
}
