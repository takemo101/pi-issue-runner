#!/usr/bin/env bats
# tmux.sh のテスト

setup() {
    load '../helpers/mocks'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/lib/config.sh"
    source "$PROJECT_ROOT/lib/tmux.sh"
}

@test "generate_session_name creates correct format" {
    run generate_session_name 42
    [ "$status" -eq 0 ]
    [ "$output" = "pi-issue-42" ]
}

@test "generate_session_name uses custom prefix" {
    export PI_RUNNER_TMUX_SESSION_PREFIX="custom"
    _CONFIG_LOADED=""
    load_config
    
    run generate_session_name 99
    [ "$status" -eq 0 ]
    [ "$output" = "custom-issue-99" ]
    
    unset PI_RUNNER_TMUX_SESSION_PREFIX
}

@test "session_exists returns false for non-existent session" {
    setup_mocks
    mock_tmux
    
    run session_exists "non-existent-session"
    [ "$status" -eq 1 ]
    
    cleanup_mocks
}

@test "create_session function exists" {
    run type create_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "kill_session function exists" {
    run type kill_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "attach_session function exists" {
    run type attach_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}
