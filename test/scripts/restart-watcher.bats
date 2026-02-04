#!/usr/bin/env bats
# restart-watcher.sh のBatsテスト (Issue #693)

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
# 基本機能テスト
# ====================

@test "restart-watcher.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/restart-watcher.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "restart-watcher.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/restart-watcher.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "restart-watcher.sh requires session name or issue number" {
    run "$PROJECT_ROOT/scripts/restart-watcher.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "restart-watcher.sh fails for non-existent session" {
    # tmuxのhas-sessionが失敗するようにモック
    echo '#!/usr/bin/env bash' > "$MOCK_DIR/tmux"
    echo 'if [[ "$1" == "has-session" ]]; then exit 1; fi' >> "$MOCK_DIR/tmux"
    echo 'echo "mock tmux: $*"' >> "$MOCK_DIR/tmux"
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
    
    run "$PROJECT_ROOT/scripts/restart-watcher.sh" 999
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ====================
# Issue番号からセッション名への変換テスト
# ====================

@test "restart-watcher.sh accepts issue number" {
    skip "Requires complex daemon and tmux mocking - tested in manual/integration tests"
}

@test "restart-watcher.sh accepts session name" {
    skip "Requires complex daemon and tmux mocking - tested in manual/integration tests"
}

# ====================
# PID管理テスト
# ====================

@test "restart-watcher.sh saves watcher PID" {
    skip "Requires daemon functionality - tested in manual/integration tests"
}

@test "restart-watcher.sh stops existing watcher before starting new one" {
    skip "Requires daemon functionality - tested in manual/integration tests"
}

@test "restart-watcher.sh handles orphaned watchers" {
    skip "Requires pkill functionality - tested in manual/integration tests"
}

# ====================
# エラーハンドリングテスト
# ====================

@test "restart-watcher.sh fails if watch-session.sh not found" {
    # セッション存在をモック
    echo '#!/usr/bin/env bash' > "$MOCK_DIR/tmux"
    echo 'if [[ "$1" == "has-session" ]]; then exit 0; fi' >> "$MOCK_DIR/tmux"
    chmod +x "$MOCK_DIR/tmux"
    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
    
    # watch-session.shを一時的に削除
    local mock_watcher="$PROJECT_ROOT/scripts/watch-session.sh"
    local mock_watcher_backup="${mock_watcher}.bak"
    
    if [[ -f "$mock_watcher" ]]; then
        mv "$mock_watcher" "$mock_watcher_backup"
    fi
    
    run "$PROJECT_ROOT/scripts/restart-watcher.sh" 42
    
    # 復元
    if [[ -f "$mock_watcher_backup" ]]; then
        mv "$mock_watcher_backup" "$mock_watcher"
    fi
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}
