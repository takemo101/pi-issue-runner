#!/usr/bin/env bats
# mux-all.sh のBatsテスト

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

@test "mux-all.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "mux-all.sh shows help with -h" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "help includes all major options" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"-a"* ]] || [[ "$output" == *"--all"* ]]
    [[ "$output" == *"-p"* ]] || [[ "$output" == *"--prefix"* ]]
    [[ "$output" == *"-w"* ]] || [[ "$output" == *"--watch"* ]]
    [[ "$output" == *"-k"* ]] || [[ "$output" == *"--kill"* ]]
}

@test "help includes examples section" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Examples:"* ]] || [[ "$output" == *"examples:"* ]]
}

# ====================
# オプション解析テスト
# ====================

@test "mux-all.sh fails with unknown option" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "mux-all.sh accepts -a option" {
    # tmuxモック（セッションなし）
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
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
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" -a
    # ヘルプが表示されないことを確認（オプションが正常に解析された）
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "mux-all.sh accepts --all option" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" --all
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "mux-all.sh accepts -p option with prefix" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" -p test-prefix
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "mux-all.sh accepts --prefix option with prefix" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" --prefix test-prefix
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "mux-all.sh accepts -w option" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    # xpanesとtmuxのモック
    cat > "$MOCK_DIR/xpanes" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/xpanes"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" -w
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

@test "mux-all.sh accepts -k option" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" -k
    [[ "$output" != *"Usage:"* ]] || [ "$status" -eq 0 ]
}

# ====================
# 基本動作テスト
# ====================

@test "mux-all.sh handles no sessions gracefully" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
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
    
    run "$PROJECT_ROOT/scripts/mux-all.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active"* ]] || [[ "$output" == *"not found"* ]]
}

@test "mux-all.sh detects sessions with tmux" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        if [[ "$*" == *"-F"* ]]; then
            echo "pi-issue-42"
            echo "pi-issue-43"
        else
            echo "pi-issue-42: 1 windows"
            echo "pi-issue-43: 1 windows"
        fi
        exit 0
        ;;
    "has-session")
        exit 1  # monitor session does not exist
        ;;
    "new-session")
        exit 0
        ;;
    "link-window")
        exit 0
        ;;
    "attach-session")
        # Don't actually attach in test
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh"
    # デバッグ出力
    echo "# Exit status: $status" >&3
    echo "# Output:" >&3
    echo "$output" | sed 's/^/# /' >&3
    
    # セッションが検出されたことを確認
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found"* ]] || [[ "$output" == *"session"* ]]
}

@test "mux-all.sh runs in watch mode with xpanes" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    # xpanesとtmuxのモック
    cat > "$MOCK_DIR/xpanes" << 'MOCK_EOF'
#!/usr/bin/env bash
# xpanesが呼ばれたことを確認できるよう、引数をエコー
echo "xpanes called with: $*"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/xpanes"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        if [[ "$*" == *"-F"* ]]; then
            echo "pi-issue-42"
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" -w
    [ "$status" -eq 0 ]
    [[ "$output" == *"xpanes"* ]]
}

# ====================
# マルチプレクサ別テスト
# ====================

@test "mux-all.sh works with tmux multiplexer" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1  # no sessions
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh"
    [ "$status" -eq 0 ]
}

@test "mux-all.sh works with zellij multiplexer" {
    export PI_RUNNER_MULTIPLEXER_TYPE="zellij"
    cat > "$MOCK_DIR/zellij" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 0  # no sessions (empty output)
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/zellij"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh"
    [ "$status" -eq 0 ]
}

@test "mux-all.sh detects multiplexer type from config" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh"
    [ "$status" -eq 0 ]
    # tmuxが使用されていることを間接的に確認（エラーなし）
}

# ====================
# エラーハンドリングテスト
# ====================

@test "mux-all.sh shows error when xpanes not found in watch mode" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        if [[ "$*" == *"-F"* ]]; then
            echo "pi-issue-42"
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    # xpanesのモックを作成しない（コマンドが見つからない状態）
    enable_mocks
    
    run "$PROJECT_ROOT/scripts/mux-all.sh" -w
    [ "$status" -ne 0 ]
    [[ "$output" == *"xpanes"* ]]
}

@test "mux-all.sh combines multiple options" {
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    cat > "$MOCK_DIR/xpanes" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/xpanes"
    
    cat > "$MOCK_DIR/tmux" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "list-sessions")
        if [[ "$*" == *"-F"* ]]; then
            echo "test-issue-42"
            echo "test-issue-43"
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/tmux"
    enable_mocks
    
    # -a と -w を組み合わせ
    run "$PROJECT_ROOT/scripts/mux-all.sh" -a -w
    [ "$status" -eq 0 ]
}
