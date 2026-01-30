#!/usr/bin/env bats
# config.sh のテスト

setup() {
    load '../helpers/mocks'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/lib/config.sh"
}

@test "get_config returns default worktree_base_dir" {
    # デフォルト値をリセット
    unset PI_RUNNER_WORKTREE_BASE_DIR
    _CONFIG_LOADED=""
    
    run get_config worktree_base_dir
    [ "$status" -eq 0 ]
    [ "$output" = ".worktrees" ]
}

@test "get_config returns default tmux_session_prefix" {
    unset PI_RUNNER_TMUX_SESSION_PREFIX
    _CONFIG_LOADED=""
    
    run get_config tmux_session_prefix
    [ "$status" -eq 0 ]
    [ "$output" = "pi" ]
}

@test "get_config returns default pi_command" {
    unset PI_RUNNER_PI_COMMAND
    _CONFIG_LOADED=""
    
    run get_config pi_command
    [ "$status" -eq 0 ]
    [ "$output" = "pi" ]
}

@test "get_config returns empty for unknown key" {
    run get_config unknown_key
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "environment variable overrides default" {
    export PI_RUNNER_WORKTREE_BASE_DIR="custom_dir"
    _CONFIG_LOADED=""
    
    run get_config worktree_base_dir
    [ "$status" -eq 0 ]
    [ "$output" = "custom_dir" ]
    
    unset PI_RUNNER_WORKTREE_BASE_DIR
}

@test "load_config sets _CONFIG_LOADED" {
    _CONFIG_LOADED=""
    load_config
    [ "$_CONFIG_LOADED" = "true" ]
}
