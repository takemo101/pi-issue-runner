#!/usr/bin/env bats
# watch-session.sh のBatsテスト

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

@test "watch-session.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "watch-session.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes --marker option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--marker"* ]]
}

@test "help includes --interval option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--interval"* ]]
}

@test "help includes --cleanup-args option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--cleanup-args"* ]]
}

@test "help includes --no-auto-attach option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-auto-attach"* ]]
}

@test "help includes description" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Description:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "watch-session.sh fails without session name" {
    run "$PROJECT_ROOT/scripts/watch-session.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "watch-session.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================
# セッション存在チェックテスト
# ====================

@test "watch-session.sh fails when session not found" {
    # tmuxモック - セッション存在しない
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 1  # セッション存在しない
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/watch-session.sh" pi-issue-42
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Session"* ]]
}

# ====================
# Issue番号抽出テスト
# ====================

@test "watch-session.sh extracts issue number from session name" {
    # tmuxモック - セッション存在するがすぐ終了
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        if [[ "$3" == "pi-issue-invalid" ]]; then
            exit 0  # セッション存在
        fi
        exit 0
        ;;
    "capture-pane")
        echo "some output"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    # Issue番号が抽出できないセッション名でエラー
    run "$PROJECT_ROOT/scripts/watch-session.sh" invalid-session-name
    # セッションが存在しないか、Issue番号抽出エラーのいずれか
    [ "$status" -ne 0 ]
}

# ====================
# マーカー検出テスト
# ====================

@test "help explains completion marker format" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"TASK_COMPLETE"* ]] || [[ "$output" == *"completion marker"* ]] || [[ "$output" == *"完了"* ]]
}

@test "help explains error marker detection" {
    run "$PROJECT_ROOT/scripts/watch-session.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"TASK_ERROR"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"エラー"* ]]
}
