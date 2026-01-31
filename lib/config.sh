#!/usr/bin/env bash
# config.sh - 設定ファイル読み込み（Bash 4.0以上）

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

# 共通YAMLパーサーを読み込み
_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CONFIG_LIB_DIR/yaml.sh"

# 設定読み込みフラグ（重複呼び出し防止）
_CONFIG_LOADED=""

# デフォルト設定
CONFIG_WORKTREE_BASE_DIR="${CONFIG_WORKTREE_BASE_DIR:-.worktrees}"
CONFIG_WORKTREE_COPY_FILES="${CONFIG_WORKTREE_COPY_FILES:-.env .env.local .envrc}"
CONFIG_TMUX_SESSION_PREFIX="${CONFIG_TMUX_SESSION_PREFIX:-pi}"
CONFIG_TMUX_START_IN_SESSION="${CONFIG_TMUX_START_IN_SESSION:-true}"
CONFIG_PI_COMMAND="${CONFIG_PI_COMMAND:-pi}"
CONFIG_PI_ARGS="${CONFIG_PI_ARGS:-}"
CONFIG_PARALLEL_MAX_CONCURRENT="${CONFIG_PARALLEL_MAX_CONCURRENT:-0}"  # 0 = unlimited

# 設定ファイルを探す
find_config_file() {
    local start_dir="${1:-.}"
    local config_name=".pi-runner.yaml"
    local current_dir
    current_dir="$(cd "$start_dir" && pwd)"

    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/$config_name" ]]; then
            echo "$current_dir/$config_name"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    return 1
}

# YAML設定を読み込む
load_config() {
    # 重複呼び出し防止
    if [[ "$_CONFIG_LOADED" == "true" ]]; then
        return 0
    fi
    
    local config_file="${1:-}"
    
    if [[ -z "$config_file" ]]; then
        if config_file="$(find_config_file "$(pwd)" 2>/dev/null)"; then
            :  # ファイルが見つかった
        else
            config_file=""
        fi
    fi

    if [[ -n "$config_file" && -f "$config_file" ]]; then
        _parse_config_file "$config_file"
    fi
    
    # 環境変数による上書き
    _apply_env_overrides
    
    _CONFIG_LOADED="true"
}

# 設定ファイルをパース（yaml.shを使用）
_parse_config_file() {
    local config_file="$1"
    
    # 単一値の取得
    local value
    
    value="$(yaml_get "$config_file" ".worktree.base_dir" "")"
    if [[ -n "$value" ]]; then
        CONFIG_WORKTREE_BASE_DIR="$value"
    fi
    
    value="$(yaml_get "$config_file" ".tmux.session_prefix" "")"
    if [[ -n "$value" ]]; then
        CONFIG_TMUX_SESSION_PREFIX="$value"
    fi
    
    value="$(yaml_get "$config_file" ".tmux.start_in_session" "")"
    if [[ -n "$value" ]]; then
        CONFIG_TMUX_START_IN_SESSION="$value"
    fi
    
    value="$(yaml_get "$config_file" ".pi.command" "")"
    if [[ -n "$value" ]]; then
        CONFIG_PI_COMMAND="$value"
    fi
    
    value="$(yaml_get "$config_file" ".parallel.max_concurrent" "")"
    if [[ -n "$value" ]]; then
        CONFIG_PARALLEL_MAX_CONCURRENT="$value"
    fi
    
    # 配列値の取得
    _parse_array_configs "$config_file"
}

# 配列設定をパース
_parse_array_configs() {
    local config_file="$1"
    
    # worktree.copy_files
    local copy_files_list=""
    while IFS= read -r item; do
        if [[ -n "$item" ]]; then
            if [[ -z "$copy_files_list" ]]; then
                copy_files_list="$item"
            else
                copy_files_list="$copy_files_list $item"
            fi
        fi
    done < <(yaml_get_array "$config_file" ".worktree.copy_files")
    
    if [[ -n "$copy_files_list" ]]; then
        CONFIG_WORKTREE_COPY_FILES="$copy_files_list"
    fi
    
    # pi.args
    local pi_args_list=""
    while IFS= read -r item; do
        if [[ -n "$item" ]]; then
            if [[ -z "$pi_args_list" ]]; then
                pi_args_list="$item"
            else
                pi_args_list="$pi_args_list $item"
            fi
        fi
    done < <(yaml_get_array "$config_file" ".pi.args")
    
    if [[ -n "$pi_args_list" ]]; then
        CONFIG_PI_ARGS="$pi_args_list"
    fi
}

# 環境変数による上書き
_apply_env_overrides() {
    if [[ -n "${PI_RUNNER_WORKTREE_BASE_DIR:-}" ]]; then
        CONFIG_WORKTREE_BASE_DIR="$PI_RUNNER_WORKTREE_BASE_DIR"
    fi
    if [[ -n "${PI_RUNNER_WORKTREE_COPY_FILES:-}" ]]; then
        CONFIG_WORKTREE_COPY_FILES="$PI_RUNNER_WORKTREE_COPY_FILES"
    fi
    if [[ -n "${PI_RUNNER_TMUX_SESSION_PREFIX:-}" ]]; then
        CONFIG_TMUX_SESSION_PREFIX="$PI_RUNNER_TMUX_SESSION_PREFIX"
    fi
    if [[ -n "${PI_RUNNER_TMUX_START_IN_SESSION:-}" ]]; then
        CONFIG_TMUX_START_IN_SESSION="$PI_RUNNER_TMUX_START_IN_SESSION"
    fi
    if [[ -n "${PI_RUNNER_PI_COMMAND:-}" ]]; then
        CONFIG_PI_COMMAND="$PI_RUNNER_PI_COMMAND"
    fi
    if [[ -n "${PI_RUNNER_PI_ARGS:-}" ]]; then
        CONFIG_PI_ARGS="$PI_RUNNER_PI_ARGS"
    fi
    if [[ -n "${PI_RUNNER_PARALLEL_MAX_CONCURRENT:-}" ]]; then
        CONFIG_PARALLEL_MAX_CONCURRENT="$PI_RUNNER_PARALLEL_MAX_CONCURRENT"
    fi
}

# 設定値を取得
get_config() {
    local key="$1"
    case "$key" in
        worktree_base_dir)
            echo "$CONFIG_WORKTREE_BASE_DIR"
            ;;
        worktree_copy_files)
            echo "$CONFIG_WORKTREE_COPY_FILES"
            ;;
        tmux_session_prefix)
            echo "$CONFIG_TMUX_SESSION_PREFIX"
            ;;
        tmux_start_in_session)
            echo "$CONFIG_TMUX_START_IN_SESSION"
            ;;
        pi_command)
            echo "$CONFIG_PI_COMMAND"
            ;;
        pi_args)
            echo "$CONFIG_PI_ARGS"
            ;;
        parallel_max_concurrent)
            echo "$CONFIG_PARALLEL_MAX_CONCURRENT"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 設定の再読み込み（テスト用）
reload_config() {
    _CONFIG_LOADED=""
    load_config "$@"
}

# 設定を表示（デバッグ用）
show_config() {
    echo "=== Configuration ==="
    echo "worktree_base_dir: $CONFIG_WORKTREE_BASE_DIR"
    echo "worktree_copy_files: $CONFIG_WORKTREE_COPY_FILES"
    echo "tmux_session_prefix: $CONFIG_TMUX_SESSION_PREFIX"
    echo "tmux_start_in_session: $CONFIG_TMUX_START_IN_SESSION"
    echo "pi_command: $CONFIG_PI_COMMAND"
    echo "pi_args: $CONFIG_PI_ARGS"
}
