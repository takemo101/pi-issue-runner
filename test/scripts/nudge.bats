#!/usr/bin/env bats
# nudge.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    export ORIGINAL_PATH="$PATH"
    
    # テストではtmuxを使用
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    unset _CONFIG_LOADED
    unset _MUX_TYPE
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
# ヘルプオプションテスト
# ====================

@test "nudge.sh --help returns success" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --help
    [ "$status" -eq 0 ]
}

@test "nudge.sh --help shows usage" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "nudge.sh --help shows session-name argument" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --help
    [[ "$output" == *"session-name"* ]] || [[ "$output" == *"issue-number"* ]]
}

@test "nudge.sh --help shows message option" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --help
    [[ "$output" == *"--message"* ]] || [[ "$output" == *"-m"* ]]
}

@test "nudge.sh --help shows session option" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --help
    [[ "$output" == *"--session"* ]] || [[ "$output" == *"-s"* ]]
}

@test "nudge.sh --help shows examples" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --help
    [[ "$output" == *"Examples:"* ]] || [[ "$output" == *"example"* ]]
}

@test "nudge.sh -h returns success" {
    run "$PROJECT_ROOT/scripts/nudge.sh" -h
    [ "$status" -eq 0 ]
}

# ====================
# エラーケーステスト
# ====================

@test "nudge.sh without argument fails" {
    run "$PROJECT_ROOT/scripts/nudge.sh"
    [ "$status" -ne 0 ]
}

@test "nudge.sh without argument shows error message" {
    run "$PROJECT_ROOT/scripts/nudge.sh"
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "nudge.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/nudge.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "nudge.sh with empty message fails" {
    run "$PROJECT_ROOT/scripts/nudge.sh" 42 --message ""
    [ "$status" -ne 0 ]
}

@test "nudge.sh with both target and --session fails" {
    run "$PROJECT_ROOT/scripts/nudge.sh" 42 --session pi-issue-42
    [ "$status" -ne 0 ]
}

# ====================
# スクリプト構造テスト
# ====================

@test "nudge.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/nudge.sh"
    [ "$status" -eq 0 ]
}

@test "nudge.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh sources multiplexer.sh" {
    grep -q "lib/multiplexer.sh" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh has send_nudge function" {
    grep -q "send_nudge()" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh sources session-resolver.sh" {
    grep -q "session-resolver.sh" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh uses resolve_session_target" {
    grep -q "resolve_session_target" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh has default message" {
    grep -q "DEFAULT_MESSAGE" "$PROJECT_ROOT/scripts/nudge.sh"
}

@test "nudge.sh uses mux_send_keys function" {
    grep -q "mux_send_keys" "$PROJECT_ROOT/scripts/nudge.sh"
}

# ====================
# 機能テスト（モック使用）
# ====================

@test "nudge.sh sends message to session by issue number" {
    # tmuxコマンドのモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # セッションが存在する
        ;;
    "send-keys")
        echo "tmux send-keys called: $*"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/nudge.sh" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sending nudge"* ]]
}

@test "nudge.sh sends message to session by session name" {
    # tmuxコマンドのモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # セッションが存在する
        ;;
    "send-keys")
        echo "tmux send-keys called: $*"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/nudge.sh" pi-issue-42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sending nudge"* ]]
}

@test "nudge.sh sends custom message" {
    # tmuxコマンドのモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # セッションが存在する
        ;;
    "send-keys")
        echo "tmux send-keys called: $*"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/nudge.sh" 42 --message "カスタムメッセージ"
    [ "$status" -eq 0 ]
    [[ "$output" == *"カスタムメッセージ"* ]]
}

@test "nudge.sh fails when session does not exist" {
    # tmuxコマンドのモック（セッションが存在しない）
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 1  # セッションが存在しない
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/nudge.sh" 42
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Session not found"* ]]
}

@test "nudge.sh works with --session option" {
    # tmuxコマンドのモック
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # セッションが存在する
        ;;
    "send-keys")
        echo "tmux send-keys called: $*"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/nudge.sh" --session pi-issue-42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sending nudge"* ]]
}

@test "nudge.sh sends default message when no --message specified" {
    # tmuxコマンドのモック（実際に送信されるメッセージを検証）
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # セッションが存在する
        ;;
    "send-keys")
        # デフォルトメッセージが含まれているか確認
        if [[ "$*" == *"続けてください"* ]]; then
            exit 0
        else
            echo "Expected default message not found in: $*"
            exit 1
        fi
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/nudge.sh" 42
    [ "$status" -eq 0 ]
}
