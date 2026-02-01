#!/usr/bin/env bats
# cleanup-plans.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用ディレクトリ設定
    export TEST_PLANS_DIR="$BATS_TEST_TMPDIR/docs/plans"
    mkdir -p "$TEST_PLANS_DIR"
    
    # cleanup_closed_issue_plans用のハードコードされたパス（docs/plans）
    # カレントディレクトリをBATSTESTTMPDIRに変更してテスト
    export TEST_CWD="$BATS_TEST_TMPDIR"
    
    # モックディレクトリ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # config.shを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            plans_dir) echo "$TEST_PLANS_DIR" ;;
            plans_keep_recent) echo "5" ;;
            *) echo "" ;;
        esac
    }
    
    # load_config をオーバーライド（何もしない）
    load_config() {
        :
    }
    
    # cleanup-plans.shを読み込み
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

# ====================
# cleanup_old_plans テスト（計画書なし）
# ====================

@test "cleanup_old_plans returns 0 with no plans" {
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files found"* ]]
}

@test "cleanup_old_plans handles non-existent directory" {
    rm -rf "$TEST_PLANS_DIR"
    
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
}

# ====================
# cleanup_old_plans テスト（保持件数以下）
# ====================

@test "cleanup_old_plans keeps all when under limit" {
    # 3件の計画書を作成（保持件数5より少ない）
    touch "$TEST_PLANS_DIR/issue-1-plan.md"
    touch "$TEST_PLANS_DIR/issue-2-plan.md"
    touch "$TEST_PLANS_DIR/issue-3-plan.md"
    
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
    
    # すべてのファイルが保持されている
    [ -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
}

@test "cleanup_old_plans shows keeping message when under limit" {
    touch "$TEST_PLANS_DIR/issue-1-plan.md"
    touch "$TEST_PLANS_DIR/issue-2-plan.md"
    
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"keeping all"* ]]
}

# ====================
# cleanup_old_plans テスト（保持件数超過）
# ====================

@test "cleanup_old_plans removes old files when over limit" {
    # 7件の計画書を作成（時間差をつける）
    for i in 1 2 3 4 5 6 7; do
        local file="$TEST_PLANS_DIR/issue-$i-plan.md"
        echo "Plan $i" > "$file"
        # タイムスタンプを変えて順序をつける（小さいほど古い）
        touch -t "20200101000$i" "$file"
    done
    
    # keep_count=3 で実行
    run cleanup_old_plans "false" "3"
    [ "$status" -eq 0 ]
    
    # 最新3件（issue-5, issue-6, issue-7）は保持
    [ -f "$TEST_PLANS_DIR/issue-5-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-6-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-7-plan.md" ]
    
    # 古い4件（issue-1〜4）は削除
    [ ! -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ ! -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ ! -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
    [ ! -f "$TEST_PLANS_DIR/issue-4-plan.md" ]
}

@test "cleanup_old_plans reports deleted count" {
    for i in 1 2 3 4 5; do
        local file="$TEST_PLANS_DIR/issue-$i-plan.md"
        echo "Plan $i" > "$file"
        touch -t "20200101000$i" "$file"
    done
    
    run cleanup_old_plans "false" "2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deleted 3 old plan(s)"* ]]
}

# ====================
# cleanup_old_plans dry-run テスト
# ====================

@test "cleanup_old_plans dry-run does not delete files" {
    for i in 1 2 3 4 5; do
        local file="$TEST_PLANS_DIR/issue-$i-plan.md"
        echo "Plan $i" > "$file"
        touch -t "20200101000$i" "$file"
    done
    
    run cleanup_old_plans "true" "2"
    [ "$status" -eq 0 ]
    
    # dry-runなので全てのファイルが残っている
    [ -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-4-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-5-plan.md" ]
}

@test "cleanup_old_plans dry-run outputs DRY-RUN message" {
    for i in 1 2 3; do
        local file="$TEST_PLANS_DIR/issue-$i-plan.md"
        echo "Plan $i" > "$file"
        touch -t "20200101000$i" "$file"
    done
    
    run cleanup_old_plans "true" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
}

# ====================
# cleanup_old_plans keep_count=0 テスト
# ====================

@test "cleanup_old_plans with keep_count=0 keeps all" {
    touch "$TEST_PLANS_DIR/issue-1-plan.md"
    touch "$TEST_PLANS_DIR/issue-2-plan.md"
    touch "$TEST_PLANS_DIR/issue-3-plan.md"
    
    run cleanup_old_plans "false" "0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"keeping all plans"* ]]
    
    # すべてのファイルが保持されている
    [ -f "$TEST_PLANS_DIR/issue-1-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-2-plan.md" ]
    [ -f "$TEST_PLANS_DIR/issue-3-plan.md" ]
}

# ====================
# cleanup_closed_issue_plans テスト
# ====================

# ghコマンドのモック（クローズされたIssue）
mock_gh_closed_issue() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "issue view 100 --json state -q .state"*)
        echo "CLOSED"
        ;;
    "issue view 101 --json state -q .state"*)
        echo "OPEN"
        ;;
    "issue view 102 --json state -q .state"*)
        echo "CLOSED"
        ;;
    "issue view"*"--json state"*)
        echo "OPEN"
        ;;
    *)
        echo "OPEN"
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# cleanup_closed_issue_plans は hardcoded された "docs/plans" を使用
# テスト用にカレントディレクトリを変更してテスト

@test "cleanup_closed_issue_plans returns 0 with no plans" {
    mock_gh_closed_issue
    export PATH="$MOCK_DIR:$PATH"
    
    # docs/plans ディレクトリを一時ディレクトリに作成
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    
    cd "$BATS_TEST_TMPDIR"
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files found"* ]]
}

@test "cleanup_closed_issue_plans removes closed issue plans" {
    mock_gh_closed_issue
    export PATH="$MOCK_DIR:$PATH"
    
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-100-plan.md"  # CLOSED
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-101-plan.md"  # OPEN
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-102-plan.md"  # CLOSED
    
    cd "$BATS_TEST_TMPDIR"
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # CLOSEDのIssueの計画書は削除
    [ ! -f "$BATS_TEST_TMPDIR/docs/plans/issue-100-plan.md" ]
    [ ! -f "$BATS_TEST_TMPDIR/docs/plans/issue-102-plan.md" ]
    
    # OPENのIssueの計画書は保持
    [ -f "$BATS_TEST_TMPDIR/docs/plans/issue-101-plan.md" ]
}

@test "cleanup_closed_issue_plans dry-run preserves files" {
    mock_gh_closed_issue
    export PATH="$MOCK_DIR:$PATH"
    
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-100-plan.md"  # CLOSED
    
    cd "$BATS_TEST_TMPDIR"
    run cleanup_closed_issue_plans "true"
    [ "$status" -eq 0 ]
    
    # dry-runなのでファイルは残っている
    [ -f "$BATS_TEST_TMPDIR/docs/plans/issue-100-plan.md" ]
    [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "cleanup_closed_issue_plans reports count" {
    mock_gh_closed_issue
    export PATH="$MOCK_DIR:$PATH"
    
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-100-plan.md"  # CLOSED
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-102-plan.md"  # CLOSED
    
    cd "$BATS_TEST_TMPDIR"
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deleted 2 plan file(s)"* ]]
}

@test "cleanup_closed_issue_plans shows no closed message" {
    mock_gh_closed_issue
    export PATH="$MOCK_DIR:$PATH"
    
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-101-plan.md"  # OPEN
    
    cd "$BATS_TEST_TMPDIR"
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No closed issue plans found"* ]]
}

# ====================
# cleanup_closed_issue_plans gh CLI エラーテスト
# ====================

@test "cleanup_closed_issue_plans fails without gh CLI" {
    # command -v gh で gh が見つからないようにする
    # ghという名前のシェル関数で上書きし、command -vで検出されないようにする
    
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    touch "$BATS_TEST_TMPDIR/docs/plans/issue-100-plan.md"
    
    cd "$BATS_TEST_TMPDIR"
    
    # cleanup_closed_issue_plansを再定義してghチェックをテスト
    # command -v gh が失敗するように環境を作る
    # PATH を基本コマンドのみにする
    local minimal_path="/usr/bin:/bin"
    
    # ghがこのパスに存在しないことを確認
    if ! PATH="$minimal_path" command -v gh &>/dev/null; then
        PATH="$minimal_path" run cleanup_closed_issue_plans "false"
        [ "$status" -eq 1 ]
        [[ "$output" == *"GitHub CLI (gh) is not installed"* ]]
    else
        skip "gh is available in minimal PATH, cannot test gh absence"
    fi
}

# ====================
# cleanup_closed_issue_plans handles non-existent directory
# ====================

@test "cleanup_closed_issue_plans handles non-existent plans directory" {
    mock_gh_closed_issue
    export PATH="$MOCK_DIR:$PATH"
    
    # docs/plans が存在しないことを確認
    rm -rf "$BATS_TEST_TMPDIR/docs/plans"
    
    cd "$BATS_TEST_TMPDIR"
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plans directory found"* ]]
}

# ====================
# エッジケーステスト
# ====================

@test "cleanup_old_plans ignores non-matching files" {
    # 計画書パターンに合わないファイル
    touch "$TEST_PLANS_DIR/readme.md"
    touch "$TEST_PLANS_DIR/notes.txt"
    touch "$TEST_PLANS_DIR/issue-plan.md"  # 番号がない
    
    # 正しいパターンのファイル
    for i in 1 2 3; do
        local file="$TEST_PLANS_DIR/issue-$i-plan.md"
        echo "Plan $i" > "$file"
        touch -t "20200101000$i" "$file"
    done
    
    run cleanup_old_plans "false" "1"
    [ "$status" -eq 0 ]
    
    # 非計画書ファイルは残っている
    [ -f "$TEST_PLANS_DIR/readme.md" ]
    [ -f "$TEST_PLANS_DIR/notes.txt" ]
    [ -f "$TEST_PLANS_DIR/issue-plan.md" ]
}

@test "cleanup_old_plans uses default keep_count from config" {
    # 設定からの保持件数（5件）を使用
    for i in 1 2 3 4 5 6 7; do
        local file="$TEST_PLANS_DIR/issue-$i-plan.md"
        echo "Plan $i" > "$file"
        touch -t "20200101000$i" "$file"
    done
    
    # keep_countパラメータなし
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
    
    # 7件中2件が削除され、5件が保持
    local count=0
    for i in 1 2 3 4 5 6 7; do
        if [ -f "$TEST_PLANS_DIR/issue-$i-plan.md" ]; then
            count=$((count + 1))
        fi
    done
    [ "$count" -eq 5 ]
}
