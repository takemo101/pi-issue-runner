#!/usr/bin/env bats
# cleanup.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# ヘルプ表示テスト
# ====================

@test "cleanup.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "cleanup.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "cleanup.sh requires issue number" {
    run "$PROJECT_ROOT/scripts/cleanup.sh"
    [ "$status" -ne 0 ]
}

# ====================
# オプションテスト
# ====================

@test "cleanup.sh accepts --force option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--force"* ]] || [[ "$output" == *"-f"* ]]
}

@test "cleanup.sh accepts --delete-branch option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--delete-branch"* ]]
}

@test "cleanup.sh accepts --keep-session option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--keep-session"* ]]
}

@test "cleanup.sh accepts --keep-worktree option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--keep-worktree"* ]]
}

@test "cleanup.sh accepts --orphans option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--orphans"* ]]
}

@test "cleanup.sh accepts --dry-run option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--dry-run"* ]]
}

@test "cleanup.sh accepts --delete-plans option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--delete-plans"* ]]
}

@test "cleanup.sh accepts --all option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--all"* ]]
}

@test "cleanup.sh accepts --age option" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --help
    [[ "$output" == *"--age"* ]]
}

# ====================
# --orphans オプションテスト
# ====================

@test "cleanup.sh --orphans finds no orphans in empty status dir" {
    # 一時ディレクトリでテスト
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
    
    cd "$BATS_TEST_TMPDIR"
    git init --bare test-repo.git &>/dev/null
    cd test-repo.git
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --orphans
    [ "$status" -eq 0 ]
    [[ "$output" == *"No orphaned status files found"* ]]
}

@test "cleanup.sh --orphans --dry-run shows what would be deleted" {
    # 一時ディレクトリでテスト
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
    
    # 孤立したステータスファイルを作成
    echo '{"issue": 999, "status": "complete"}' > "${BATS_TEST_TMPDIR}/.worktrees/.status/999.json"
    
    cd "$BATS_TEST_TMPDIR"
    git init --bare test-repo.git &>/dev/null
    cd test-repo.git
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --orphans --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
    [[ "$output" == *"999"* ]]
    
    # ファイルが削除されていないことを確認
    [ -f "${BATS_TEST_TMPDIR}/.worktrees/.status/999.json" ]
}

@test "cleanup.sh --orphans deletes orphaned status files" {
    # 一時ディレクトリでテスト
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
    
    # 孤立したステータスファイルを作成
    echo '{"issue": 888, "status": "complete"}' > "${BATS_TEST_TMPDIR}/.worktrees/.status/888.json"
    
    cd "$BATS_TEST_TMPDIR"
    git init --bare test-repo.git &>/dev/null
    cd test-repo.git
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --orphans
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removing orphaned status file"* ]]
    
    # ファイルが削除されたことを確認
    [ ! -f "${BATS_TEST_TMPDIR}/.worktrees/.status/888.json" ]
}

# ====================
# --delete-plans オプションテスト
# ====================

@test "cleanup.sh --delete-plans with no plans directory" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p test-repo && cd test-repo
    git init &>/dev/null
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --delete-plans
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plans directory found"* ]]
}

@test "cleanup.sh --delete-plans with empty plans directory" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p test-repo/docs/plans && cd test-repo
    git init &>/dev/null
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --delete-plans
    [ "$status" -eq 0 ]
    [[ "$output" == *"No plan files found"* ]]
}

# ====================
# --all オプションテスト
# ====================

@test "cleanup.sh --all runs both orphans and delete-plans cleanup" {
    # 一時ディレクトリでテスト
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
    mkdir -p "${BATS_TEST_TMPDIR}/docs/plans"
    
    # 孤立したステータスファイルを作成
    echo '{"issue": 777, "status": "complete"}' > "${BATS_TEST_TMPDIR}/.worktrees/.status/777.json"
    
    cd "$BATS_TEST_TMPDIR"
    git init &>/dev/null
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Full Cleanup"* ]]
    [[ "$output" == *"orphaned status files"* ]]
    [[ "$output" == *"plans"* ]]
}

@test "cleanup.sh --all --dry-run does not delete files" {
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
    
    echo '{"issue": 666, "status": "complete"}' > "${BATS_TEST_TMPDIR}/.worktrees/.status/666.json"
    
    cd "$BATS_TEST_TMPDIR"
    git init &>/dev/null
    create_minimal_config "."
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --all --dry-run
    [ "$status" -eq 0 ]
    
    # ファイルが削除されていないことを確認
    [ -f "${BATS_TEST_TMPDIR}/.worktrees/.status/666.json" ]
}

# ====================
# --age オプションテスト
# ====================

@test "cleanup.sh --age requires a number" {
    run "$PROJECT_ROOT/scripts/cleanup.sh" --orphans --age
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires"* ]]
}

@test "cleanup.sh --orphans --age filters by file age" {
    export PI_RUNNER_WORKTREE_BASE_DIR="${BATS_TEST_TMPDIR}/.worktrees"
    mkdir -p "${BATS_TEST_TMPDIR}/.worktrees/.status"
    
    # 新しいファイルを作成
    echo '{"issue": 555, "status": "complete"}' > "${BATS_TEST_TMPDIR}/.worktrees/.status/555.json"
    
    cd "$BATS_TEST_TMPDIR"
    git init &>/dev/null
    create_minimal_config "."
    
    # --age 0 は "0日より古い" = 今日作成されたファイルは対象外
    run "$PROJECT_ROOT/scripts/cleanup.sh" --orphans --age 0 --dry-run
    [ "$status" -eq 0 ]
    # 新しいファイルなので対象外
    [[ "$output" != *"555"* ]] || [[ "$output" == *"No orphaned status files"* ]]
}

# ====================
# --improve-logs オプションテスト
# ====================

@test "cleanup.sh --improve-logs: cleans up improve-logs directory" {
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir/.improve-logs"
    
    # Create test log files
    for i in $(seq 1 15); do
        echo "test" > "$test_dir/.improve-logs/iteration-$i-20260203-$(printf '%02d' $i)0000.log"
    done
    
    # Create config with keep_recent=10
    cat > "$test_dir/.pi-runner.yaml" << 'YAML'
improve_logs:
  keep_recent: 10
  keep_days: 0
YAML
    
    cd "$test_dir"
    run "$PROJECT_ROOT/scripts/cleanup.sh" --improve-logs
    [ "$status" -eq 0 ]
    
    # Should keep 10 files
    local remaining=$(find "$test_dir/.improve-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 10 ]
}

@test "cleanup.sh --improve-logs --age 7: deletes old logs" {
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir/.improve-logs"
    
    # Create old log (modify timestamp to 10 days ago)
    local old_log="$test_dir/.improve-logs/iteration-1-20260120-120000.log"
    echo "old" > "$old_log"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -t "$(date -v-10d +%Y%m%d%H%M.%S)" "$old_log" 2>/dev/null || skip "touch -t failed on macOS"
    else
        touch -t "$(date -d '10 days ago' +%Y%m%d%H%M.%S)" "$old_log" 2>/dev/null || skip "touch -t failed on Linux"
    fi
    
    # Create recent log
    local new_log="$test_dir/.improve-logs/iteration-2-20260203-120000.log"
    echo "new" > "$new_log"
    
    # Create config
    cat > "$test_dir/.pi-runner.yaml" << 'YAML'
improve_logs:
  keep_recent: 0
  keep_days: 0
YAML
    
    cd "$test_dir"
    run "$PROJECT_ROOT/scripts/cleanup.sh" --improve-logs --age 7
    [ "$status" -eq 0 ]
    
    # Old file should be deleted
    [ ! -f "$old_log" ]
    [ -f "$new_log" ]
}

@test "cleanup.sh --improve-logs --dry-run: shows but doesn't delete" {
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir/.improve-logs"
    
    # Create test log files
    for i in $(seq 1 15); do
        echo "test" > "$test_dir/.improve-logs/iteration-$i-20260203-$(printf '%02d' $i)0000.log"
    done
    
    # Create config
    cat > "$test_dir/.pi-runner.yaml" << 'YAML'
improve_logs:
  keep_recent: 5
  keep_days: 0
YAML
    
    cd "$test_dir"
    run "$PROJECT_ROOT/scripts/cleanup.sh" --improve-logs --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
    [[ "$output" == *"Would delete"* ]]
    
    # All files should still exist
    local remaining=$(find "$test_dir/.improve-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 15 ]
}

@test "cleanup.sh --all: includes improve-logs cleanup" {
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir/.improve-logs"
    
    # Create test log files
    for i in $(seq 1 5); do
        echo "test" > "$test_dir/.improve-logs/iteration-$i-20260203-$(printf '%02d' $i)0000.log"
    done
    
    # Create config
    cat > "$test_dir/.pi-runner.yaml" << 'YAML'
improve_logs:
  keep_recent: 10
  keep_days: 7
YAML
    
    cd "$test_dir"
    git init &>/dev/null
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"improve-logs"* ]]
}

@test "cleanup.sh --improve-logs: no directory - success" {
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir"
    
    # Create minimal config
    cat > "$test_dir/.pi-runner.yaml" << 'YAML'
improve_logs:
  keep_recent: 10
YAML
    
    cd "$test_dir"
    run "$PROJECT_ROOT/scripts/cleanup.sh" --improve-logs
    [ "$status" -eq 0 ]
    # Success is sufficient - debug messages may not appear in output
}

@test "cleanup.sh --improve-logs: respects custom directory" {
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir/custom-logs"
    
    # Create test log files in custom directory
    for i in $(seq 1 10); do
        echo "test" > "$test_dir/custom-logs/iteration-$i-20260203-$(printf '%02d' $i)0000.log"
    done
    
    # Create config with custom directory
    cat > "$test_dir/.pi-runner.yaml" << 'YAML'
improve_logs:
  keep_recent: 5
  keep_days: 0
  dir: custom-logs
YAML
    
    cd "$test_dir"
    run "$PROJECT_ROOT/scripts/cleanup.sh" --improve-logs
    [ "$status" -eq 0 ]
    
    # Should keep 5 files in custom directory
    local remaining=$(find "$test_dir/custom-logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$remaining" -eq 5 ]
}

# ====================
# Issue #1068: Watcher log cleanup
# ====================

@test "Issue #1068: cleanup.sh removes watcher log files" {
    # 高速モード時はスキップ
    if [[ "${BATS_FAST_MODE:-}" == "1" ]]; then
        skip "Skipping slow test in fast mode"
    fi
    
    # モック環境セットアップ
    mock_gh
    mock_git
    mock_tmux
    enable_mocks
    
    local test_dir="${BATS_TEST_TMPDIR}/test-project"
    mkdir -p "$test_dir"
    
    # Create minimal git repo
    cd "$test_dir"
    git init &>/dev/null
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "test" > README.md
    git add README.md
    git commit -m "Initial commit" &>/dev/null
    create_minimal_config "."
    
    # Create watcher log file (use TMPDIR to match cleanup.sh behavior)
    local watcher_log="${TMPDIR:-/tmp}/pi-watcher-pi-issue-999.log"
    echo "test log content" > "$watcher_log"
    
    # Verify log file exists
    [ -f "$watcher_log" ]
    
    # Mock status file
    local status_dir="${test_dir}/.pi-status"
    mkdir -p "$status_dir"
    cat > "$status_dir/999.json" << 'JSON'
{
  "issue_number": "999",
  "session_name": "pi-issue-999",
  "worktree_path": ".worktrees/issue-999-test",
  "branch_name": "issue-999-test",
  "status": "running"
}
JSON
    
    # Run cleanup
    run "$PROJECT_ROOT/scripts/cleanup.sh" 999 --keep-session
    
    # Verify watcher log file was removed
    [ ! -f "$watcher_log" ]
    
    # Cleanup
    rm -f "$watcher_log" 2>/dev/null || true
}
