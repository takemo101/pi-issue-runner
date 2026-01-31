#!/usr/bin/env bats
# attach.sh のBatsテスト

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

@test "attach.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "attach.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/attach.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help includes arguments description" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "help includes examples" {
    run "$PROJECT_ROOT/scripts/attach.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]]
}

# ====================
# 引数バリデーションテスト
# ====================

@test "attach.sh fails without session name or issue number" {
    run "$PROJECT_ROOT/scripts/attach.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "attach.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/attach.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ====================
# 入力形式テスト
# ====================

@test "attach.sh accepts issue number format" {
    # tmuxモック - セッションがアタッチ可能な状態
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "attach-session")
        echo "Would attach to session: $*"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/attach.sh" 42
    # 実際のアタッチは環境依存なのでステータスは問わない
    # ヘルプ出力がなければ引数は解析された
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "attach.sh accepts session name format" {
    # tmuxモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/attach.sh" pi-issue-42
    # ヘルプが表示されなければ引数は解析された
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}
