#!/usr/bin/env bash
# config.sh - 設定ファイル読み込み（Bash 3互換）

# Note: set -euo pipefail はsource先の環境に影響するため、
# このファイルでは設定しない（呼び出し元で設定）

# 設定読み込みフラグ（重複呼び出し防止）
_CONFIG_LOADED=""

# デフォルト設定
CONFIG_WORKTREE_BASE_DIR="${CONFIG_WORKTREE_BASE_DIR:-.worktrees}"
CONFIG_WORKTREE_COPY_FILES="${CONFIG_WORKTREE_COPY_FILES:-.env .env.local .envrc}"
CONFIG_TMUX_SESSION_PREFIX="${CONFIG_TMUX_SESSION_PREFIX:-pi}"
CONFIG_TMUX_START_IN_SESSION="${CONFIG_TMUX_START_IN_SESSION:-true}"
CONFIG_PI_COMMAND="${CONFIG_PI_COMMAND:-pi}"
CONFIG_PI_ARGS="${CONFIG_PI_ARGS:-}"

# 設定ファイルを探す
find_config_file() {
    local start_dir="${1:-.}"
    local config_name=".pi-runner.yml"
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

# YAML設定を読み込む（簡易パーサー）
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

# 設定ファイルをパース
_parse_config_file() {
    local config_file="$1"
    local section=""
    local in_copy_files=false
    local in_pi_args=false
    local copy_files_list=""
    local pi_args_list=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # セクションの検出
        if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            in_copy_files=false
            in_pi_args=false
            continue
        fi

        # キーと値の解析
        if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # クォートを除去
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # 配列開始の検出
            if [[ -z "$value" ]]; then
                case "${section}_${key}" in
                    worktree_copy_files)
                        in_copy_files=true
                        in_pi_args=false
                        ;;
                    pi_args)
                        in_pi_args=true
                        in_copy_files=false
                        ;;
                esac
                continue
            fi
            
            in_copy_files=false
            in_pi_args=false
            
            case "${section}_${key}" in
                worktree_base_dir)
                    CONFIG_WORKTREE_BASE_DIR="$value"
                    ;;
                worktree_copy_files)
                    # スペース区切りの単一行形式
                    CONFIG_WORKTREE_COPY_FILES="$value"
                    ;;
                tmux_session_prefix)
                    CONFIG_TMUX_SESSION_PREFIX="$value"
                    ;;
                tmux_start_in_session)
                    CONFIG_TMUX_START_IN_SESSION="$value"
                    ;;
                pi_command)
                    CONFIG_PI_COMMAND="$value"
                    ;;
                pi_args)
                    # スペース区切りの単一行形式
                    CONFIG_PI_ARGS="$value"
                    ;;
            esac
            continue
        fi

        # 配列項目の解析
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
            local item="${BASH_REMATCH[1]}"
            item="${item#\"}"
            item="${item%\"}"
            item="${item#\'}"
            item="${item%\'}"
            
            if [[ "$in_copy_files" == "true" ]]; then
                if [[ -z "$copy_files_list" ]]; then
                    copy_files_list="$item"
                else
                    copy_files_list="$copy_files_list $item"
                fi
            elif [[ "$in_pi_args" == "true" ]]; then
                if [[ -z "$pi_args_list" ]]; then
                    pi_args_list="$item"
                else
                    pi_args_list="$pi_args_list $item"
                fi
            fi
        fi
    done < "$config_file"
    
    # 配列を設定（先頭スペースなし）
    if [[ -n "$copy_files_list" ]]; then
        CONFIG_WORKTREE_COPY_FILES="$copy_files_list"
    fi
    if [[ -n "$pi_args_list" ]]; then
        CONFIG_PI_ARGS="$pi_args_list"
    fi
}

# 環境変数による上書き
_apply_env_overrides() {
    [[ -n "${PI_RUNNER_WORKTREE_BASE_DIR:-}" ]] && CONFIG_WORKTREE_BASE_DIR="$PI_RUNNER_WORKTREE_BASE_DIR"
    [[ -n "${PI_RUNNER_WORKTREE_COPY_FILES:-}" ]] && CONFIG_WORKTREE_COPY_FILES="$PI_RUNNER_WORKTREE_COPY_FILES"
    [[ -n "${PI_RUNNER_TMUX_SESSION_PREFIX:-}" ]] && CONFIG_TMUX_SESSION_PREFIX="$PI_RUNNER_TMUX_SESSION_PREFIX"
    [[ -n "${PI_RUNNER_TMUX_START_IN_SESSION:-}" ]] && CONFIG_TMUX_START_IN_SESSION="$PI_RUNNER_TMUX_START_IN_SESSION"
    [[ -n "${PI_RUNNER_PI_COMMAND:-}" ]] && CONFIG_PI_COMMAND="$PI_RUNNER_PI_COMMAND"
    [[ -n "${PI_RUNNER_PI_ARGS:-}" ]] && CONFIG_PI_ARGS="$PI_RUNNER_PI_ARGS"
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
