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
    unset PI_RUNNER_WORKTREE_BASE_DIR
    unset PI_RUNNER_TMUX_SESSION_PREFIX
    
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
