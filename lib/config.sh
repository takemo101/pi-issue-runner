#!/usr/bin/env bash
# config.sh - 設定ファイル読み込み（Bash 3互換）

set -euo pipefail

# デフォルト設定
CONFIG_WORKTREE_BASE_DIR="${CONFIG_WORKTREE_BASE_DIR:-.worktrees}"
CONFIG_WORKTREE_COPY_FILES="${CONFIG_WORKTREE_COPY_FILES:-.env .env.local .envrc}"
CONFIG_TMUX_SESSION_PREFIX="${CONFIG_TMUX_SESSION_PREFIX:-pi-issue}"
CONFIG_TMUX_START_IN_SESSION="${CONFIG_TMUX_START_IN_SESSION:-true}"
CONFIG_PI_COMMAND="${CONFIG_PI_COMMAND:-pi}"
CONFIG_PI_ARGS="${CONFIG_PI_ARGS:-}"

# 設定ファイルを探す
find_config_file() {
    local start_dir="${1:-.}"
    local config_name=".pi-issue-runner.yml"
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
    local config_file="${1:-}"
    
    if [[ -z "$config_file" ]]; then
        config_file="$(find_config_file "$(pwd)")" || return 0
    fi

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    local section=""
    local copy_files_list=""
    local pi_args_list=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメントと空行をスキップ
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # セクションの検出
        if [[ "$line" =~ ^([a-z_]+): ]]; then
            section="${BASH_REMATCH[1]}"
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
            
            case "${section}_${key}" in
                worktree_base_dir)
                    CONFIG_WORKTREE_BASE_DIR="$value"
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
            esac
        fi

        # 配列の解析（copy_files, args）
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
            local item="${BASH_REMATCH[1]}"
            item="${item#\"}"
            item="${item%\"}"
            
            case "$section" in
                worktree)
                    copy_files_list="$copy_files_list $item"
                    ;;
                pi)
                    pi_args_list="$pi_args_list $item"
                    ;;
            esac
        fi
    done < "$config_file"
    
    # 配列をマージ
    if [[ -n "$copy_files_list" ]]; then
        CONFIG_WORKTREE_COPY_FILES="$copy_files_list"
    fi
    if [[ -n "$pi_args_list" ]]; then
        CONFIG_PI_ARGS="$pi_args_list"
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
        *)
            echo ""
            ;;
    esac
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
