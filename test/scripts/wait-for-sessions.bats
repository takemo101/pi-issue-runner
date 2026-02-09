#!/usr/bin/env bats
# wait-for-sessions.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # テスト用worktreeディレクトリを設定
    export TEST_WORKTREE_DIR="$BATS_TEST_TMPDIR/.worktrees"
    mkdir -p "$TEST_WORKTREE_DIR/.status"
    export PI_RUNNER_WORKTREE_BASE_DIR="$TEST_WORKTREE_DIR"
}

teardown() {
    unset PI_RUNNER_WORKTREE_BASE_DIR
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプ表示テスト
# ====================

@test "wait-for-sessions.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "wait-for-sessions.sh without arguments returns exit code 3" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh"
    [ "$status" -eq 3 ]
}

@test "wait-for-sessions.sh with invalid issue number returns exit code 3" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" "abc"
    [ "$status" -eq 3 ]
}

# ====================
# すべて完了済みテスト
# ====================

@test "wait-for-sessions.sh returns 0 when all complete" {
    # 完了ステータスを作成
    cat > "$TEST_WORKTREE_DIR/.status/200.json" << 'EOF'
{
  "issue": 200,
  "status": "complete",
  "session": "pi-issue-200",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    cat > "$TEST_WORKTREE_DIR/.status/201.json" << 'EOF'
{
  "issue": 201,
  "status": "complete",
  "session": "pi-issue-201",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 200 201 --interval 1 --timeout 5 --quiet
    [ "$status" -eq 0 ]
}

# ====================
# エラーセッションテスト
# ====================

@test "wait-for-sessions.sh returns 1 when session has error" {
    cat > "$TEST_WORKTREE_DIR/.status/300.json" << 'EOF'
{
  "issue": 300,
  "status": "error",
  "session": "pi-issue-300",
  "error_message": "Test error",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 300 --interval 1 --timeout 5 --quiet
    [ "$status" -eq 1 ]
}

# ====================
# タイムアウトテスト
# ====================

@test "wait-for-sessions.sh returns 2 on timeout" {
    # 実行中のままのステータス（セッションが存在する場合はタイムアウト）
    cat > "$TEST_WORKTREE_DIR/.status/400.json" << 'EOF'
{
  "issue": 400,
  "status": "running",
  "session": "pi-issue-400",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    # tmuxモックでセッションが存在するように設定
    mkdir -p "$BATS_TEST_TMPDIR/mock_bin"
    cat > "$BATS_TEST_TMPDIR/mock_bin/tmux" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    "has-session") exit 0 ;;  # セッションが存在する
    *) exit 0 ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock_bin/tmux"
    
    PATH="$BATS_TEST_TMPDIR/mock_bin:$PATH" \
        run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 400 --interval 1 --timeout 2 --quiet
    [ "$status" -eq 2 ]
}

@test "wait-for-sessions.sh detects stale running session (session vanished)" {
    # ステータスは running だがセッションが存在しない → エラー検出
    cat > "$TEST_WORKTREE_DIR/.status/400.json" << 'EOF'
{
  "issue": 400,
  "status": "running",
  "session": "pi-issue-400",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 400 --interval 1 --timeout 5
    [ "$status" -eq 1 ]
    [[ "$output" == *"セッション消滅"* ]]
}

# ====================
# fail-fast テスト
# ====================

@test "wait-for-sessions.sh --fail-fast returns 1 immediately on error" {
    cat > "$TEST_WORKTREE_DIR/.status/500.json" << 'EOF'
{
  "issue": 500,
  "status": "running",
  "session": "pi-issue-500",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    cat > "$TEST_WORKTREE_DIR/.status/501.json" << 'EOF'
{
  "issue": 501,
  "status": "error",
  "session": "pi-issue-501",
  "error_message": "Immediate failure",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    # tmuxモックでセッション500が存在するように設定
    mkdir -p "$BATS_TEST_TMPDIR/mock_bin"
    cat > "$BATS_TEST_TMPDIR/mock_bin/tmux" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    "has-session") exit 0 ;;  # セッションが存在する
    *) exit 0 ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/mock_bin/tmux"

    PATH="$BATS_TEST_TMPDIR/mock_bin:$PATH" \
        run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 500 501 --interval 1 --timeout 10 --fail-fast --quiet
    [ "$status" -eq 1 ]
}

# ====================
# 混合ステータステスト
# ====================

@test "wait-for-sessions.sh returns 1 for mixed status (complete + error)" {
    cat > "$TEST_WORKTREE_DIR/.status/600.json" << 'EOF'
{
  "issue": 600,
  "status": "complete",
  "session": "pi-issue-600",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    cat > "$TEST_WORKTREE_DIR/.status/601.json" << 'EOF'
{
  "issue": 601,
  "status": "error",
  "session": "pi-issue-601",
  "error_message": "Failed",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 600 601 --interval 1 --timeout 5 --quiet
    [ "$status" -eq 1 ]
}

# ====================
# unknownステータステスト（Issue #238）
# ====================

@test "wait-for-sessions.sh treats unknown status without tmux session as complete" {
    # ステータスファイルがない（unknown状態）
    # かつ tmux セッションも存在しない場合は完了として扱う
    # Issue番号 700 はステータスファイルもtmuxセッションもない
    
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 700 --interval 1 --timeout 3 --quiet
    [ "$status" -eq 0 ]
}

@test "wait-for-sessions.sh treats mixed unknown (no session) + complete as success" {
    # 1つは完了、もう1つはunknown（セッションなし）
    cat > "$TEST_WORKTREE_DIR/.status/800.json" << 'EOF'
{
  "issue": 800,
  "status": "complete",
  "session": "pi-issue-800",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF
    # 801 はステータスファイルがない（unknown）かつtmuxセッションもない
    
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 800 801 --interval 1 --timeout 3 --quiet
    [ "$status" -eq 0 ]
}

# ====================
# --cleanup オプションテスト (Issue #247)
# ====================

@test "wait-for-sessions.sh --help shows --cleanup option" {
    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--cleanup"* ]]
}

@test "wait-for-sessions.sh handles --cleanup option" {
    grep -q '\-\-cleanup)' "$PROJECT_ROOT/scripts/wait-for-sessions.sh"
}

@test "wait-for-sessions.sh --cleanup logs auto-cleanup message" {
    # 完了ステータスを作成
    cat > "$TEST_WORKTREE_DIR/.status/900.json" << 'EOF'
{
  "issue": 900,
  "status": "complete",
  "session": "pi-issue-900",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 900 --interval 1 --timeout 5 --cleanup
    [ "$status" -eq 0 ]
    [[ "$output" == *"Auto-cleanup enabled"* ]]
}

@test "wait-for-sessions.sh --cleanup calls cleanup for completed sessions" {
    # 完了ステータスを作成
    cat > "$TEST_WORKTREE_DIR/.status/901.json" << 'EOF'
{
  "issue": 901,
  "status": "complete",
  "session": "pi-issue-901",
  "timestamp": "2024-01-01T00:00:00Z"
}
EOF

    run "$PROJECT_ROOT/scripts/wait-for-sessions.sh" 901 --interval 1 --timeout 5 --cleanup
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaning up worktree"* ]]
}
