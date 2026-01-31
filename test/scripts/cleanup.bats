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
    
    run "$PROJECT_ROOT/scripts/cleanup.sh" --orphans
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removing orphaned status file"* ]]
    
    # ファイルが削除されたことを確認
    [ ! -f "${BATS_TEST_TMPDIR}/.worktrees/.status/888.json" ]
}
