#!/usr/bin/env bats
# cleanup-plans.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用ディレクトリを設定
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    export TEST_PLANS_DIR="$BATS_TEST_TMPDIR/docs/plans"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    mkdir -p "$TEST_PLANS_DIR"
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # ライブラリを読み込み
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/cleanup-plans.sh"
    
    # get_config をオーバーライド
    get_config() {
        case "$1" in
            worktree_base_dir) echo "$TEST_WORKTREE_DIR" ;;
            plans_dir) echo "$TEST_PLANS_DIR" ;;
            plans_keep_recent) echo "5" ;;
            *) echo "" ;;
        esac
    }
    
    # load_config をオーバーライド
    load_config() {
        :
    }
    
    # ログレベルをINFOに設定（テストで出力をキャプチャするため）
    LOG_LEVEL="INFO"
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

# ghコマンドのモックを拡張
mock_gh_with_issues() {
    local mock_script="$MOCK_DIR/gh"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
    "issue view 100 --json state -q .state"*)
        echo "OPEN"
        ;;
    "issue view 101 --json state -q .state"*)
        echo "CLOSED"
        ;;
    "issue view 102 --json state -q .state"*)
        echo "CLOSED"
        ;;
    "issue view 103 --json state -q .state"*)
        echo "OPEN"
        ;;
    "issue view 999 --json state -q .state"*)
        echo "UNKNOWN"
        ;;
    *)
        echo "OPEN"
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    export PATH="$MOCK_DIR:$PATH"
}

# 計画書ファイルを作成するヘルパー
create_plan_file() {
    local issue_number="$1"
    local age_seconds="${2:-0}"
    
    local file="$TEST_PLANS_DIR/issue-${issue_number}-plan.md"
    echo "# Plan for Issue #${issue_number}" > "$file"
    
    if [[ "$age_seconds" -gt 0 ]]; then
        # macOS/BSD互換: touchで過去の日時を設定
        local past_date
        past_date=$(date -v-${age_seconds}S +"%Y%m%d%H%M.%S" 2>/dev/null || date -d "-${age_seconds} seconds" +"%Y%m%d%H%M.%S" 2>/dev/null || echo "")
        if [[ -n "$past_date" ]]; then
            touch -t "${past_date%.*}" "$file" 2>/dev/null || true
        fi
    fi
}

# ====================
# cleanup_old_plans dry_run=true テスト
# ====================

@test "cleanup_old_plans dry_run=true does not delete files" {
    # 6個の計画書を作成（keep_count=5を超える）
    for i in {1..6}; do
        create_plan_file "$i" "$((i * 100))"
    done
    
    run cleanup_old_plans "true" "5"
    [ "$status" -eq 0 ]
    
    # 全てのファイルが残っていることを確認
    [ "$(ls -1 "$TEST_PLANS_DIR" | wc -l | tr -d ' ')" -eq 6 ]
}

@test "cleanup_old_plans dry_run=true shows DRY-RUN message" {
    for i in {1..6}; do
        create_plan_file "$i" "$((i * 100))"
    done
    
    run cleanup_old_plans "true" "5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
}

# ====================
# cleanup_old_plans dry_run=false テスト
# ====================

@test "cleanup_old_plans dry_run=false deletes old files" {
    # 6個の計画書を作成（異なる更新時刻）
    for i in {1..6}; do
        create_plan_file "$i" "$((i * 10))"
        sleep 0.1  # 順序を保証するため
    done
    
    run cleanup_old_plans "false" "5"
    [ "$status" -eq 0 ]
    
    # 5個以下のファイルが残っていることを確認
    local count
    count="$(ls -1 "$TEST_PLANS_DIR" | wc -l | tr -d ' ')"
    [ "$count" -le 5 ]
}

@test "cleanup_old_plans shows deleted message" {
    for i in {1..6}; do
        create_plan_file "$i" "$((i * 10))"
        sleep 0.1
    done
    
    run cleanup_old_plans "false" "5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Delet"* ]] || [[ "$output" == *"delet"* ]]
}

# ====================
# keep_count=0 テスト
# ====================

@test "cleanup_old_plans with keep_count=0 keeps all files" {
    for i in {1..10}; do
        create_plan_file "$i"
    done
    
    run cleanup_old_plans "false" "0"
    [ "$status" -eq 0 ]
    
    # 全てのファイルが残っていることを確認
    [ "$(ls -1 "$TEST_PLANS_DIR" | wc -l | tr -d ' ')" -eq 10 ]
    [[ "$output" == *"keeping all plans"* ]]
}

# ====================
# keep_count 以下のファイル数テスト
# ====================

@test "cleanup_old_plans does nothing when file count <= keep_count" {
    for i in {1..3}; do
        create_plan_file "$i"
    done
    
    run cleanup_old_plans "false" "5"
    [ "$status" -eq 0 ]
    
    # 全てのファイルが残っていることを確認
    [ "$(ls -1 "$TEST_PLANS_DIR" | wc -l | tr -d ' ')" -eq 3 ]
    [[ "$output" == *"keeping all"* ]]
}

# ====================
# 計画書ディレクトリなしテスト
# ====================

@test "cleanup_old_plans handles missing plans directory" {
    rm -rf "$TEST_PLANS_DIR"
    
    run cleanup_old_plans "false" "5"
    [ "$status" -eq 0 ]
}

# ====================
# 空のディレクトリテスト
# ====================

@test "cleanup_old_plans handles empty plans directory" {
    run cleanup_old_plans "false" "5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files found"* ]]
}

# ====================
# cleanup_closed_issue_plans dry_run=true テスト
# ====================

@test "cleanup_closed_issue_plans dry_run=true does not delete files" {
    mock_gh_with_issues
    
    # cleanup_closed_issue_plans は docs/plans をハードコードで使用
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-101-plan.md
    
    run cleanup_closed_issue_plans "true"
    [ "$status" -eq 0 ]
    
    # ファイルが残っていることを確認
    [ -f "docs/plans/issue-101-plan.md" ]
}

@test "cleanup_closed_issue_plans dry_run=true shows DRY-RUN message for closed issues" {
    mock_gh_with_issues
    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-101-plan.md
    
    run cleanup_closed_issue_plans "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
    [[ "$output" == *"101"* ]]
}

# ====================
# cleanup_closed_issue_plans dry_run=false テスト
# ====================

@test "cleanup_closed_issue_plans dry_run=false deletes closed issue plans" {
    mock_gh_with_issues
    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-101-plan.md
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # ファイルが削除されていることを確認
    [ ! -f "docs/plans/issue-101-plan.md" ]
}

@test "cleanup_closed_issue_plans preserves open issue plans" {
    mock_gh_with_issues
    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-100-plan.md
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # ファイルが残っていることを確認
    [ -f "docs/plans/issue-100-plan.md" ]
}

@test "cleanup_closed_issue_plans handles mixed cases" {
    mock_gh_with_issues
    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-100-plan.md  # OPEN
    echo "# Plan" > docs/plans/issue-101-plan.md  # CLOSED
    echo "# Plan" > docs/plans/issue-102-plan.md  # CLOSED
    echo "# Plan" > docs/plans/issue-103-plan.md  # OPEN
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    
    # オープン中は保持、クローズ済みは削除
    [ -f "docs/plans/issue-100-plan.md" ]
    [ ! -f "docs/plans/issue-101-plan.md" ]
    [ ! -f "docs/plans/issue-102-plan.md" ]
    [ -f "docs/plans/issue-103-plan.md" ]
}

# ====================
# gh コマンドなしテスト
# ====================

@test "cleanup_closed_issue_plans fails without gh command" {
    # ghをモックせずに、PATHから除外
    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
    
    # ghが存在しないようにモック
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 127
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    
    # 実際のghをテスト環境から隠す
    export PATH="$MOCK_DIR"
    
    # command -v gh が失敗するようにする
    unset -f command 2>/dev/null || true
    
    # ghが見つからない場合のテストは、実際に存在しない場合のみ実行
    if ! command -v gh &> /dev/null; then
        create_plan_file "100"
        
        run cleanup_closed_issue_plans "false"
        [ "$status" -eq 1 ]
        [[ "$output" == *"not installed"* ]] || [[ "$output" == *"GitHub CLI"* ]]
    else
        skip "gh command is installed, cannot test missing gh scenario"
    fi
}

# ====================
# 計画書ディレクトリなしテスト
# ====================

@test "cleanup_closed_issue_plans handles missing plans directory" {
    mock_gh_with_issues
    
    # cleanup_closed_issue_plans は docs/plans をハードコードで使用
    # 存在しないディレクトリに移動してテスト
    cd "$BATS_TEST_TMPDIR"
    rm -rf docs/plans 2>/dev/null || true
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plans directory"* ]]
}

# ====================
# 空のディレクトリテスト
# ====================

@test "cleanup_closed_issue_plans handles empty plans directory" {
    mock_gh_with_issues
    
    # テスト用に docs/plans を作成（cleanup_closed_issue_plans はハードコードでこのパスを使用）
    mkdir -p "$BATS_TEST_TMPDIR/docs/plans"
    cd "$BATS_TEST_TMPDIR"
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files"* ]]
}

# ====================
# エッジケーステスト
# ====================

@test "cleanup_old_plans with keep_count=1 keeps only newest" {
    # 3個の計画書を作成（異なる更新時刻）
    create_plan_file "10" "300"  # 最も古い
    sleep 0.2
    create_plan_file "20" "200"
    sleep 0.2
    create_plan_file "30" "100"  # 最も新しい
    
    run cleanup_old_plans "false" "1"
    [ "$status" -eq 0 ]
    
    # 1個のファイルだけが残っていることを確認
    local count
    count="$(ls -1 "$TEST_PLANS_DIR" | wc -l | tr -d ' ')"
    [ "$count" -eq 1 ]
}

@test "cleanup_closed_issue_plans shows count of deleted files" {
    mock_gh_with_issues
    
    # 複数のクローズ済みIssue用計画書
    mkdir -p "docs/plans"
    echo "# Plan" > "docs/plans/issue-101-plan.md"
    echo "# Plan" > "docs/plans/issue-102-plan.md"
    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    echo "# Plan" > docs/plans/issue-101-plan.md
    echo "# Plan" > docs/plans/issue-102-plan.md
    
    run cleanup_closed_issue_plans "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2"* ]] || [[ "$output" == *"Deleted"* ]]
}

@test "cleanup_old_plans uses default keep_count from config" {
    for i in {1..10}; do
        create_plan_file "$i" "$((i * 10))"
        sleep 0.05
    done
    
    # keep_count を指定せずに実行（デフォルト: 5）
    run cleanup_old_plans "false"
    [ "$status" -eq 0 ]
    
    # 5個以下のファイルが残っていることを確認
    local count
    count="$(ls -1 "$TEST_PLANS_DIR" | wc -l | tr -d ' ')"
    [ "$count" -le 5 ]
}

@test "cleanup_closed_issue_plans extracts issue number correctly" {
    mock_gh_with_issues
    
    cd "$BATS_TEST_TMPDIR"
    mkdir -p docs/plans
    
    # 正しい形式の計画書ファイル
    echo "# Plan" > docs/plans/issue-100-plan.md
    echo "# Plan" > docs/plans/issue-101-plan.md
    
    # 不正な形式のファイル（無視される）
    echo "# Other" > docs/plans/other-file.md
    echo "# Other" > docs/plans/issue-plan.md
    
    run cleanup_closed_issue_plans "true"
    [ "$status" -eq 0 ]
    
    # 正しい形式のファイルのみ処理される
    [[ "$output" == *"100"* ]] || [[ "$output" == *"101"* ]]
}
