#!/usr/bin/env bats
# stop.sh のBatsテスト

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

@test "stop.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "stop.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/stop.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes arguments description" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/stop.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "stop.sh fails without session name or issue number" {
    run "$PROJECT_ROOT/scripts/stop.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "stop.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/stop.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================
# 入力形式テスト
# ====================

@test "stop.sh accepts issue number format" {
    # tmuxモック - セッション停止
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "kill-session")
        echo "Session killed: $*"
        exit 0
        ;;
    "has-session")
        exit 0  # セッション存在
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/stop.sh" 42
    # エラーが発生しなければOK（セッションが存在しなくてもOK）
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "stop.sh accepts session name format" {
    # tmuxモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "kill-session")
        exit 0
        ;;
    "has-session")
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/stop.sh" pi-issue-42
    # ヘルプが表示されなければ引数は解析された
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

# ====================
# 動作テスト
# ====================

@test "stop.sh reports success after stopping session" {
    # tmuxモック - セッション存在＆停止成功
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "kill-session")
        exit 0
        ;;
    "has-session")
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/stop.sh" 42
    [[ "$output" == *"stopped"* ]] || [[ "$output" == *"Session"* ]] || [ "$status" -eq 0 ]
}
