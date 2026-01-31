#!/usr/bin/env bats
# tmux.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_WORKTREE_BASE_DIR
    unset CONFIG_TMUX_SESSION_PREFIX
    
    # デフォルト設定
    export PI_RUNNER_TMUX_SESSION_PREFIX="pi"
    
    # モックディレクトリをセットアップ
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

# tmuxのモック
mock_tmux_exists() {
    local mock_script="$MOCK_DIR/tmux"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 0  # セッションが存在する
        ;;
    "new-session")
        exit 0
        ;;
    "kill-session")
        exit 0
        ;;
    "attach-session")
        exit 0
        ;;
    "send-keys")
        exit 0
        ;;
    "list-sessions")
        echo "pi-issue-42: 1 windows (created ...)"
        echo "pi-issue-43: 1 windows (created ...)"
        ;;
    "capture-pane")
        echo "Mock pane content"
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

mock_tmux_not_exists() {
    local mock_script="$MOCK_DIR/tmux"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    "has-session")
        exit 1  # セッションが存在しない
        ;;
    "list-sessions")
        echo ""
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
}

# ====================
# generate_session_name テスト
# ====================

@test "generate_session_name creates correct format" {
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(generate_session_name "42")"
    [ "$result" = "pi-issue-42" ]
}

@test "generate_session_name uses custom prefix" {
    export PI_RUNNER_TMUX_SESSION_PREFIX="custom"
    unset _CONFIG_LOADED
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(generate_session_name "42")"
    [ "$result" = "custom-issue-42" ]
}

@test "generate_session_name handles prefix with -issue suffix" {
    export PI_RUNNER_TMUX_SESSION_PREFIX="test-issue"
    unset _CONFIG_LOADED
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(generate_session_name "42")"
    [ "$result" = "test-issue-42" ]
}

# ====================
# extract_issue_number テスト
# ====================

@test "extract_issue_number from standard format" {
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "pi-issue-42")"
    [ "$result" = "42" ]
}

@test "extract_issue_number from complex format" {
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "pi-issue-42-feature")"
    [ "$result" = "42" ]
}

@test "extract_issue_number from simple format" {
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(extract_issue_number "session-123")"
    [ "$result" = "123" ]
}

@test "extract_issue_number returns empty for no number" {
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run extract_issue_number "no-number-here"
    [ "$status" -ne 0 ]
}

# ====================
# session_exists テスト
# ====================

@test "session_exists returns true when session exists" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run session_exists "pi-issue-42"
    [ "$status" -eq 0 ]
}

@test "session_exists returns false when session not exists" {
    mock_tmux_not_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run session_exists "nonexistent"
    [ "$status" -ne 0 ]
}

# ====================
# create_session テスト
# ====================

@test "create_session fails when session already exists" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run create_session "pi-issue-42" "/tmp" "echo test"
    [ "$status" -ne 0 ]
}

@test "create_session succeeds when session does not exist" {
    mock_tmux_not_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run create_session "pi-issue-42" "$BATS_TEST_TMPDIR" "echo test"
    [ "$status" -eq 0 ]
}

# ====================
# list_sessions テスト
# ====================

@test "list_sessions returns matching sessions" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(list_sessions)"
    [[ "$result" == *"pi-issue-42"* ]]
}

# ====================
# kill_session テスト
# ====================

@test "kill_session succeeds for existing session" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run kill_session "pi-issue-42"
    [ "$status" -eq 0 ]
}

@test "kill_session succeeds even for non-existent session" {
    mock_tmux_not_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run kill_session "nonexistent"
    [ "$status" -eq 0 ]
}

# ====================
# get_session_output テスト
# ====================

@test "get_session_output returns pane content" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(get_session_output "pi-issue-42" 50)"
    [[ "$result" == *"Mock pane content"* ]]
}

# ====================
# count_active_sessions テスト
# ====================

@test "count_active_sessions returns session count" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    result="$(count_active_sessions)"
    [ "$result" -ge 0 ]
}

# ====================
# check_concurrent_limit テスト
# ====================

@test "check_concurrent_limit passes when no limit set" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    unset PI_RUNNER_PARALLEL_MAX_CONCURRENT
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "check_concurrent_limit passes when limit is 0" {
    mock_tmux_exists
    export PATH="$MOCK_DIR:$PATH"
    export PI_RUNNER_PARALLEL_MAX_CONCURRENT="0"
    
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    run check_concurrent_limit
    [ "$status" -eq 0 ]
}
