#!/usr/bin/env bats
# config.sh のBatsテスト

load '../test_helper'

setup() {
    # TMPDIRセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
        export _CLEANUP_TMPDIR=1
    fi
    
    # 設定をリセット
    unset _CONFIG_LOADED
    unset CONFIG_WORKTREE_BASE_DIR
    unset CONFIG_TMUX_SESSION_PREFIX
    unset CONFIG_WORKTREE_COPY_FILES
    unset CONFIG_PI_ARGS
    unset CONFIG_AGENT_TYPE
    unset CONFIG_AGENT_COMMAND
    unset CONFIG_AGENT_ARGS
    unset CONFIG_AGENT_TEMPLATE
    unset CONFIG_GITHUB_INCLUDE_COMMENTS
    unset CONFIG_GITHUB_MAX_COMMENTS
    unset PI_RUNNER_WORKTREE_BASE_DIR
    unset PI_RUNNER_TMUX_SESSION_PREFIX
    unset PI_RUNNER_AGENT_TYPE
    unset PI_RUNNER_AGENT_COMMAND
    unset PI_RUNNER_AGENT_ARGS
    unset PI_RUNNER_AGENT_TEMPLATE
    unset PI_RUNNER_GITHUB_INCLUDE_COMMENTS
    unset PI_RUNNER_GITHUB_MAX_COMMENTS
    
    # テスト用の空の設定ファイルパスを作成（find_config_fileをスキップするため）
    export TEST_CONFIG_FILE="${BATS_TEST_TMPDIR}/empty-config.yaml"
    touch "$TEST_CONFIG_FILE"
}

teardown() {
    if [[ "${_CLEANUP_TMPDIR:-}" == "1" && -d "${BATS_TEST_TMPDIR:-}" ]]; then
        rm -rf "$BATS_TEST_TMPDIR"
    fi
}

# ====================
# デフォルト値テスト
# ====================

@test "get_config returns default worktree_base_dir" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config worktree_base_dir)"
    [ "$result" = ".worktrees" ]
}

@test "get_config returns default tmux_session_prefix" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config tmux_session_prefix)"
    [ "$result" = "pi" ]
}

@test "get_config returns default pi_command" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config pi_command)"
    [ "$result" = "pi" ]
}

# ====================
# 環境変数オーバーライドテスト
# ====================

@test "environment variable overrides worktree_base_dir" {
    export PI_RUNNER_WORKTREE_BASE_DIR="custom_worktrees"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config worktree_base_dir)"
    [ "$result" = "custom_worktrees" ]
}

@test "environment variable overrides tmux_session_prefix" {
    export PI_RUNNER_TMUX_SESSION_PREFIX="custom_prefix"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config tmux_session_prefix)"
    [ "$result" = "custom_prefix" ]
}

# ====================
# _CONFIG_LOADED フラグテスト
# ====================

@test "_CONFIG_LOADED is set after load_config" {
    source "$PROJECT_ROOT/lib/config.sh"
    [ -z "${_CONFIG_LOADED:-}" ]
    load_config "$TEST_CONFIG_FILE"
    [ "$_CONFIG_LOADED" = "true" ]
}

@test "load_config does not reload when already loaded" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    # 環境変数を変更
    export PI_RUNNER_WORKTREE_BASE_DIR="should_not_apply"
    # 再度load_config（スキップされるはず）
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config worktree_base_dir)"
    # デフォルト値のままであるべき
    [ "$result" = ".worktrees" ]
}

@test "reload_config forces reload" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    original="$(get_config worktree_base_dir)"
    
    # 環境変数を設定
    export PI_RUNNER_WORKTREE_BASE_DIR="reloaded_value"
    
    # reload_configで強制リロード
    reload_config "$TEST_CONFIG_FILE"
    result="$(get_config worktree_base_dir)"
    [ "$result" = "reloaded_value" ]
}

# ====================
# 設定ファイルパースのテスト
# ====================

@test "load_config parses YAML file correctly" {
    # テスト用設定ファイルを作成
    local test_config="${BATS_TEST_TMPDIR}/test-config.yaml"
    cat > "$test_config" << 'EOF'
worktree:
  base_dir: ".custom-worktrees"

tmux:
  session_prefix: "test-prefix"

pi:
  command: "/usr/local/bin/pi"
EOF

    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    
    [ "$(get_config worktree_base_dir)" = ".custom-worktrees" ]
    [ "$(get_config tmux_session_prefix)" = "test-prefix" ]
    [ "$(get_config pi_command)" = "/usr/local/bin/pi" ]
}

@test "load_config handles array values without leading space" {
    local test_config="${BATS_TEST_TMPDIR}/array-config.yaml"
    cat > "$test_config" << 'EOF'
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env"
    - ".env.local"
    - ".envrc"

pi:
  command: "pi"
  args:
    - "--verbose"
    - "--model"
    - "gpt-4"
EOF

    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    
    # 先頭スペースがないことを確認
    copy_files="$(get_config worktree_copy_files)"
    [[ "$copy_files" != " "* ]]
    
    pi_args="$(get_config pi_args)"
    [[ "$pi_args" != " "* ]]
    
    # 値が正しいことを確認
    [ "$copy_files" = ".env .env.local .envrc" ]
    [ "$pi_args" = "--verbose --model gpt-4" ]
}

# ====================
# get_config の不明なキーテスト
# ====================

@test "get_config returns empty for unknown key" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config unknown_key)"
    [ -z "$result" ]
}

# ====================
# GitHub設定テスト
# ====================

@test "get_config returns default github_include_comments" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config github_include_comments)"
    [ "$result" = "true" ]
}

@test "get_config returns default github_max_comments" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config github_max_comments)"
    [ "$result" = "10" ]
}

@test "environment variable overrides github_include_comments" {
    export PI_RUNNER_GITHUB_INCLUDE_COMMENTS="false"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config github_include_comments)"
    [ "$result" = "false" ]
}

@test "environment variable overrides github_max_comments" {
    export PI_RUNNER_GITHUB_MAX_COMMENTS="20"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config github_max_comments)"
    [ "$result" = "20" ]
}

@test "load_config parses github settings from YAML" {
    local test_config="${BATS_TEST_TMPDIR}/github-config.yaml"
    cat > "$test_config" << 'EOF'
github:
  include_comments: false
  max_comments: 5
EOF

    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    
    [ "$(get_config github_include_comments)" = "false" ]
    [ "$(get_config github_max_comments)" = "5" ]
}

# ====================
# エージェント設定テスト
# ====================

@test "get_config returns empty agent_type by default" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config agent_type)"
    [ -z "$result" ]
}

@test "load_config parses agent section" {
    local test_config="${BATS_TEST_TMPDIR}/agent-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: claude
  command: /usr/bin/claude
  template: '{{command}} {{args}} --prompt {{prompt_file}}'
EOF

    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    
    [ "$(get_config agent_type)" = "claude" ]
    [ "$(get_config agent_command)" = "/usr/bin/claude" ]
    [[ "$(get_config agent_template)" == *'--prompt'* ]]
}

@test "load_config parses agent.args array" {
    local test_config="${BATS_TEST_TMPDIR}/agent-args-config.yaml"
    cat > "$test_config" << 'EOF'
agent:
  type: pi
  args:
    - "--verbose"
    - "--model"
    - "gpt-4"
EOF

    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$test_config"
    
    agent_args="$(get_config agent_args)"
    [ "$agent_args" = "--verbose --model gpt-4" ]
}

@test "environment variable overrides agent_type" {
    export PI_RUNNER_AGENT_TYPE="opencode"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config agent_type)"
    [ "$result" = "opencode" ]
}

@test "environment variable overrides agent_command" {
    export PI_RUNNER_AGENT_COMMAND="/custom/agent"
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config agent_command)"
    [ "$result" = "/custom/agent" ]
}

@test "environment variable overrides agent_template" {
    export PI_RUNNER_AGENT_TEMPLATE='{{command}} --custom {{prompt_file}}'
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config agent_template)"
    [[ "$result" == *'--custom'* ]]
}
