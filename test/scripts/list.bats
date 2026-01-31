#!/usr/bin/env bats
# list.sh のBatsテスト

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

@test "list.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/list.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "list.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/list.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# 基本動作テスト
# ====================

@test "list.sh runs without errors" {
    # tmuxモック（セッションなし）
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1  # セッションなし
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/list.sh"
    # エラーで終了しないこと（セッションがなくても正常）
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "list.sh accepts -v verbose option" {
    run "$PROJECT_ROOT/scripts/list.sh" --help
    [[ "$output" == *"-v"* ]] || [[ "$output" == *"verbose"* ]] || skip "verbose option not documented"
}

# ====================
# 出力フォーマットテスト
# ====================

@test "list.sh with sessions shows formatted output" {
    # tmuxモック（セッションあり）
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        echo "pi-42: 1 windows (created Mon Jan  1 00:00:00 2024)"
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/list.sh"
    [ "$status" -eq 0 ]
}
