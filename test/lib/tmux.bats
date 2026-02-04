#!/usr/bin/env bats
# tmux.sh のBatsテスト

load '../test_helper'

setup() {
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # モックディレクトリをセットアップ
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"
    
    # 元のPATHを保存
    export ORIGINAL_PATH="$PATH"
    
    # テスト用の空の設定ファイルパスを作成
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset _MUX_TYPE
    unset PI_RUNNER_TMUX_SESSION_PREFIX
    unset PI_RUNNER_PARALLEL_MAX_CONCURRENT
    
    # テストでは tmux を使用
    export PI_RUNNER_MULTIPLEXER_TYPE="tmux"
}

teardown() {
    # PATHを復元
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    
    unset PI_RUNNER_TMUX_SESSION_PREFIX
    unset PI_RUNNER_PARALLEL_MAX_CONCURRENT
    
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# generate_session_name テスト
# ====================

@test "generate_session_name with number 42" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(generate_session_name "42")"
    [ "$result" = "pi-issue-42" ]
}

@test "generate_session_name with number 123" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(generate_session_name "123")"
    [ "$result" = "pi-issue-123" ]
}

@test "generate_session_name with single digit" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(generate_session_name "1")"
    [ "$result" = "pi-issue-1" ]
}

@test "generate_session_name with custom prefix" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_TMUX_SESSION_PREFIX="myproject"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(generate_session_name "99")"
    [ "$result" = "myproject-issue-99" ]
}

@test "generate_session_name with -issue prefix (no duplicate)" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_TMUX_SESSION_PREFIX="myproject-issue"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(generate_session_name "99")"
    [ "$result" = "myproject-issue-99" ]
}

# ====================
# extract_issue_number テスト
# ====================

@test "extract_issue_number from 'pi-issue-42'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "pi-issue-42")"
    [ "$result" = "42" ]
}

@test "extract_issue_number from 'pi-issue-123'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "pi-issue-123")"
    [ "$result" = "123" ]
}

@test "extract_issue_number from 'myproject-issue-99'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "myproject-issue-99")"
    [ "$result" = "99" ]
}

@test "extract_issue_number from 'pi-issue-42-feature'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "pi-issue-42-feature")"
    [ "$result" = "42" ]
}

@test "extract_issue_number from 'pi-issue-42-fix-bug'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "pi-issue-42-fix-bug")"
    [ "$result" = "42" ]
}

@test "extract_issue_number fallback from 'session-42'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "session-42")"
    [ "$result" = "42" ]
}

@test "extract_issue_number first number fallback from 'feature123-test'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "feature123-test")"
    [ "$result" = "123" ]
}

@test "extract_issue_number returns empty for 'no-numbers-here'" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(extract_issue_number "no-numbers-here" 2>/dev/null)" || true
    [ -z "$result" ]
}

# ====================
# session_exists テスト
# ====================

@test "session_exists returns failure for nonexistent session" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    run session_exists "nonexistent-session-name-xyz123"
    [ "$status" -ne 0 ]
}

# ====================
# kill_session テスト
# ====================

@test "kill_session returns success for nonexistent session" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    run kill_session "nonexistent-session-name-xyz789"
    [ "$status" -eq 0 ]
}

@test "kill_session accepts custom max_wait parameter" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # カスタム待機時間（1秒）を指定して存在しないセッションを終了
    run kill_session "nonexistent-session-name-xyz456" 1
    [ "$status" -eq 0 ]
}

@test "kill_session sends cd /tmp before killing session (Issue #585 fix)" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    load_config "$TEST_CONFIG_FILE"
    
    # Create mock tmux command that records calls
    mkdir -p "$MOCK_DIR"
    # Use EOF without quotes to expand MOCK_DIR at creation time
    cat > "$MOCK_DIR/tmux" << EOF
#!/bin/bash
# Record the command for verification
echo "\$@" >> "${MOCK_DIR}/tmux_calls.log"

# Mock behavior for different commands
if [[ "\$1" == "has-session" ]]; then
    # First call returns success (session exists), second returns failure (killed)
    if [[ ! -f "${MOCK_DIR}/session_killed" ]]; then
        exit 0
    else
        exit 1
    fi
elif [[ "\$1" == "list-panes" ]]; then
    echo "12345"
    exit 0
elif [[ "\$1" == "send-keys" ]]; then
    # Record that cd command was sent (cd /tmp)
    if [[ "\$*" == *"cd /tmp"* ]]; then
        touch "${MOCK_DIR}/cd_sent"
    fi
    exit 0
elif [[ "\$1" == "kill-session" ]]; then
    touch "${MOCK_DIR}/session_killed"
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_DIR/tmux"
    
    # Use mock tmux
    export PATH="$MOCK_DIR:$PATH"
    
    # Run kill_session
    run kill_session "test-session" 1
    
    # Verify cd command was sent before kill
    [ -f "${MOCK_DIR}/cd_sent" ]
    [ -f "${MOCK_DIR}/session_killed" ]
    
    # Verify the order: send-keys with cd should come before kill-session
    local cd_line
    local kill_line
    cd_line=$(grep -n "send-keys.*cd /tmp" "${MOCK_DIR}/tmux_calls.log" | head -1 | cut -d: -f1)
    kill_line=$(grep -n "kill-session" "${MOCK_DIR}/tmux_calls.log" | head -1 | cut -d: -f1)
    [[ "$cd_line" -lt "$kill_line" ]]
}

# ====================
# check_concurrent_limit テスト
# ====================

@test "check_concurrent_limit with max=0 (unlimited)" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_PARALLEL_MAX_CONCURRENT="0"
    load_config "$TEST_CONFIG_FILE"
    
    run check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "check_concurrent_limit with max='' (unlimited)" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_PARALLEL_MAX_CONCURRENT=""
    load_config "$TEST_CONFIG_FILE"
    
    run check_concurrent_limit
    [ "$status" -eq 0 ]
}

@test "check_concurrent_limit with max=100 (high limit)" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    export PI_RUNNER_PARALLEL_MAX_CONCURRENT="100"
    load_config "$TEST_CONFIG_FILE"
    
    run check_concurrent_limit
    [ "$status" -eq 0 ]
}

# ====================
# count_active_sessions テスト
# ====================

@test "count_active_sessions returns a number" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi"
    load_config "$TEST_CONFIG_FILE"
    
    result="$(count_active_sessions 2>/dev/null)"
    [[ "$result" =~ ^[0-9]+$ ]]
}

# ====================
# 往復テスト（generate → extract）
# ====================

@test "round-trip for issue 1" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi-issue"
    load_config "$TEST_CONFIG_FILE"
    
    session="$(generate_session_name "1")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "1" ]
}

@test "round-trip for issue 42" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi-issue"
    load_config "$TEST_CONFIG_FILE"
    
    session="$(generate_session_name "42")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "42" ]
}

@test "round-trip for issue 99" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi-issue"
    load_config "$TEST_CONFIG_FILE"
    
    session="$(generate_session_name "99")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "99" ]
}

@test "round-trip for issue 123" {
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
    
    _CONFIG_LOADED=""
    CONFIG_TMUX_SESSION_PREFIX="pi-issue"
    load_config "$TEST_CONFIG_FILE"
    
    session="$(generate_session_name "123")"
    extracted="$(extract_issue_number "$session")"
    [ "$extracted" = "123" ]
}
