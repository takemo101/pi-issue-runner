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

@test "mux-all.sh --help exits with 0" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [ "$status" -eq 0 ]
}

@test "mux-all.sh --help shows Usage" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"usage:"* ]]
}

@test "mux-all.sh -h exits with 0" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" -h
    [ "$status" -eq 0 ]
}

@test "mux-all.sh --help shows options" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [[ "$output" == *"Options:"* ]] || [[ "$output" == *"options:"* ]]
}

# ====================
# オプション検証テスト
# ====================

@test "mux-all.sh --help mentions -a/--all option" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [[ "$output" == *"-a"* ]] && [[ "$output" == *"--all"* ]]
}

@test "mux-all.sh --help mentions -p/--prefix option" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [[ "$output" == *"-p"* ]] && [[ "$output" == *"--prefix"* ]]
}

@test "mux-all.sh --help mentions -w/--watch option" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [[ "$output" == *"-w"* ]] && [[ "$output" == *"--watch"* ]]
}

@test "mux-all.sh --help mentions -k/--kill option" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --help
    [[ "$output" == *"-k"* ]] && [[ "$output" == *"--kill"* ]]
}

# ====================
# スクリプト構造テスト
# ====================

@test "mux-all.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/scripts/mux-all.sh"
    [ "$status" -eq 0 ]
}

@test "mux-all.sh sources config.sh" {
    grep -q "lib/config.sh" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh sources log.sh" {
    grep -q "lib/log.sh" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh sources tmux.sh" {
    grep -q "lib/tmux.sh" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has main function" {
    grep -q "main()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has usage function" {
    grep -q "usage()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

# ====================
# 機能テスト（モック使用）
# ====================

@test "mux-all.sh without sessions shows no sessions message" {
    # 環境変数でマルチプレクサをtmuxに固定
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
    
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
    
    run "$PROJECT_ROOT/scripts/mux-all.sh"
    # エラー終了ではなく、警告メッセージを表示
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active"* ]] || [[ "$output" == *"no"*"session"* ]]
}

@test "mux-all.sh with unknown option fails" {
    run "$PROJECT_ROOT/scripts/mux-all.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "mux-all.sh checks multiplexer availability" {
    # check_tmux関数の呼び出しを確認
    grep -q "check_tmux" "$PROJECT_ROOT/scripts/mux-all.sh"
}

# ====================
# マルチプレクサ対応テスト
# ====================

@test "mux-all.sh has list_tmux_sessions function" {
    grep -q "list_tmux_sessions()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has list_zellij_sessions function" {
    grep -q "list_zellij_sessions()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has tmux_link_mode function" {
    grep -q "tmux_link_mode()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has zellij_default_mode function" {
    grep -q "zellij_default_mode()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has show_with_xpanes_tmux function" {
    grep -q "show_with_xpanes_tmux()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh has show_with_xpanes_zellij function" {
    grep -q "show_with_xpanes_zellij()" "$PROJECT_ROOT/scripts/mux-all.sh"
}

# ====================
# 設定とロジックテスト
# ====================

@test "mux-all.sh loads config with load_config" {
    grep -q "load_config" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh gets multiplexer_type from config" {
    grep -q "get_config multiplexer_type" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh handles MONITOR_SESSION variable" {
    grep -q "MONITOR_SESSION" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh handles WATCH_MODE variable" {
    grep -q "WATCH_MODE" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh handles ALL_SESSIONS variable" {
    grep -q "ALL_SESSIONS" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh handles PREFIX variable" {
    grep -q "PREFIX" "$PROJECT_ROOT/scripts/mux-all.sh"
}

# ====================
# xpanes統合テスト
# ====================

@test "mux-all.sh checks for xpanes command availability" {
    grep -q "command -v xpanes" "$PROJECT_ROOT/scripts/mux-all.sh"
}

@test "mux-all.sh provides xpanes installation instructions" {
    grep -q "brew install xpanes" "$PROJECT_ROOT/scripts/mux-all.sh"
}
