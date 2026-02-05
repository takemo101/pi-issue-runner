#!/usr/bin/env bash
# config.sh - 設定ファイル読み込み（Bash 4.0以上）

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_CONFIG_SH_SOURCED:-}" ]]; then
    return 0
fi
_CONFIG_SH_SOURCED="true"

# 共通YAMLパーサーを読み込み
_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CONFIG_LIB_DIR/yaml.sh"

# 設定読み込みフラグ（重複呼び出し防止）
_CONFIG_LOADED=""

# デフォルト設定
CONFIG_WORKTREE_BASE_DIR="${CONFIG_WORKTREE_BASE_DIR:-.worktrees}"
CONFIG_WORKTREE_COPY_FILES="${CONFIG_WORKTREE_COPY_FILES:-.env .env.local .envrc}"
CONFIG_MULTIPLEXER_SESSION_PREFIX="${CONFIG_MULTIPLEXER_SESSION_PREFIX:-pi}"
CONFIG_MULTIPLEXER_START_IN_SESSION="${CONFIG_MULTIPLEXER_START_IN_SESSION:-true}"
CONFIG_MULTIPLEXER_TYPE="${CONFIG_MULTIPLEXER_TYPE:-tmux}"  # tmux | zellij
CONFIG_PI_COMMAND="${CONFIG_PI_COMMAND:-pi}"
CONFIG_PI_ARGS="${CONFIG_PI_ARGS:-}"
CONFIG_PARALLEL_MAX_CONCURRENT="${CONFIG_PARALLEL_MAX_CONCURRENT:-0}"  # 0 = unlimited
CONFIG_PLANS_KEEP_RECENT="${CONFIG_PLANS_KEEP_RECENT:-10}"  # 直近N件の計画書を保持（0=全て保持）
CONFIG_PLANS_DIR="${CONFIG_PLANS_DIR:-docs/plans}"  # 計画書ディレクトリ
CONFIG_GITHUB_INCLUDE_COMMENTS="${CONFIG_GITHUB_INCLUDE_COMMENTS:-true}"  # Issueコメントを含める
CONFIG_GITHUB_MAX_COMMENTS="${CONFIG_GITHUB_MAX_COMMENTS:-10}"  # 最大コメント数（0 = 無制限）

# improve-logs クリーンアップ設定
CONFIG_IMPROVE_LOGS_KEEP_RECENT="${CONFIG_IMPROVE_LOGS_KEEP_RECENT:-10}"  # 直近N件のログを保持（0=全て保持）
CONFIG_IMPROVE_LOGS_KEEP_DAYS="${CONFIG_IMPROVE_LOGS_KEEP_DAYS:-7}"      # N日以内のログを保持（0=日数制限なし）
CONFIG_IMPROVE_LOGS_DIR="${CONFIG_IMPROVE_LOGS_DIR:-.improve-logs}"      # ログディレクトリ

# エージェント設定（マルチエージェント対応）
CONFIG_AGENT_TYPE="${CONFIG_AGENT_TYPE:-}"       # pi | claude | opencode | custom (空 = pi.commandを使用)
CONFIG_AGENT_COMMAND="${CONFIG_AGENT_COMMAND:-}" # カスタムコマンド（空 = プリセットまたはpi.commandを使用）
CONFIG_AGENT_ARGS="${CONFIG_AGENT_ARGS:-}"       # 追加引数（空 = pi.argsを使用）
CONFIG_AGENT_TEMPLATE="${CONFIG_AGENT_TEMPLATE:-}" # カスタムテンプレート（空 = プリセットを使用）

# エージェントテンプレートファイルパス設定
CONFIG_AGENTS_PLAN="${CONFIG_AGENTS_PLAN:-}"         # planステップのエージェントファイルパス
CONFIG_AGENTS_IMPLEMENT="${CONFIG_AGENTS_IMPLEMENT:-}" # implementステップのエージェントファイルパス
CONFIG_AGENTS_REVIEW="${CONFIG_AGENTS_REVIEW:-}"     # reviewステップのエージェントファイルパス
CONFIG_AGENTS_MERGE="${CONFIG_AGENTS_MERGE:-}"       # mergeステップのエージェントファイルパス
CONFIG_AGENTS_TEST="${CONFIG_AGENTS_TEST:-}"         # testステップのエージェントファイルパス
CONFIG_AGENTS_CI_FIX="${CONFIG_AGENTS_CI_FIX:-}"     # ci-fixステップのエージェントファイルパス

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

# 設定ファイルが見つかったかどうかのフラグ
_CONFIG_FILE_FOUND=""

# YAML設定を読み込む
load_config() {
    # 重複呼び出し防止
    if [[ "$_CONFIG_LOADED" == "true" ]]; then
        return 0
    fi
    
    local config_file="${1:-}"
    
    if [[ -z "$config_file" ]]; then
        if config_file="$(find_config_file "$(pwd)" 2>/dev/null)"; then
            _CONFIG_FILE_FOUND="$config_file"
        else
            config_file=""
            _CONFIG_FILE_FOUND=""
        fi
    else
        _CONFIG_FILE_FOUND="$config_file"
    fi

    if [[ -n "$config_file" && -f "$config_file" ]]; then
        _parse_config_file "$config_file"
    fi
    
    # 環境変数による上書き
    _apply_env_overrides
    
    _CONFIG_LOADED="true"
}

# 設定ファイルが見つかったかチェック（必須チェック用）
# 戻り値: 0=見つかった, 1=見つからない
# 出力: 見つかった場合はファイルパス
config_file_found() {
    if [[ -n "$_CONFIG_FILE_FOUND" ]]; then
        echo "$_CONFIG_FILE_FOUND"
        return 0
    fi
    return 1
}

# 設定ファイルが必須であることを検証
# 引数: エラー時に表示するコマンド名（オプション）
# 戻り値: 0=OK, 1=設定ファイルなし（エラー終了）
require_config_file() {
    local command_name="${1:-pi-issue-runner}"
    
    load_config
    
    if ! config_file_found >/dev/null; then
        echo "[ERROR] Configuration file '.pi-runner.yaml' not found." >&2
        echo "" >&2
        echo "This project has not been initialized for $command_name." >&2
        echo "Please run the following command to initialize:" >&2
        echo "" >&2
        echo "    pi-init" >&2
        echo "" >&2
        echo "Or create '.pi-runner.yaml' manually in your project root." >&2
        return 1
    fi
    
    return 0
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
    
    # multiplexer設定
    value="$(yaml_get "$config_file" ".multiplexer.type" "")"
    if [[ -n "$value" ]]; then
        CONFIG_MULTIPLEXER_TYPE="$value"
    fi
    
    value="$(yaml_get "$config_file" ".multiplexer.session_prefix" "")"
    if [[ -n "$value" ]]; then
        CONFIG_MULTIPLEXER_SESSION_PREFIX="$value"
    fi
    
    value="$(yaml_get "$config_file" ".multiplexer.start_in_session" "")"
    if [[ -n "$value" ]]; then
        CONFIG_MULTIPLEXER_START_IN_SESSION="$value"
    fi
    
    value="$(yaml_get "$config_file" ".pi.command" "")"
    if [[ -n "$value" ]]; then
        CONFIG_PI_COMMAND="$value"
    fi
    
    value="$(yaml_get "$config_file" ".parallel.max_concurrent" "")"
    if [[ -n "$value" ]]; then
        CONFIG_PARALLEL_MAX_CONCURRENT="$value"
    fi
    
    value="$(yaml_get "$config_file" ".plans.keep_recent" "")"
    if [[ -n "$value" ]]; then
        CONFIG_PLANS_KEEP_RECENT="$value"
    fi
    
    value="$(yaml_get "$config_file" ".plans.dir" "")"
    if [[ -n "$value" ]]; then
        CONFIG_PLANS_DIR="$value"
    fi
    
    value="$(yaml_get "$config_file" ".github.include_comments" "")"
    if [[ -n "$value" ]]; then
        CONFIG_GITHUB_INCLUDE_COMMENTS="$value"
    fi
    
    value="$(yaml_get "$config_file" ".github.max_comments" "")"
    if [[ -n "$value" ]]; then
        CONFIG_GITHUB_MAX_COMMENTS="$value"
    fi
    
    # agent セクションのパース
    value="$(yaml_get "$config_file" ".agent.type" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENT_TYPE="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agent.command" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENT_COMMAND="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agent.template" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENT_TEMPLATE="$value"
    fi
    
    # agents セクションのパース（エージェントテンプレートファイルパス）
    value="$(yaml_get "$config_file" ".agents.plan" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENTS_PLAN="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agents.implement" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENTS_IMPLEMENT="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agents.review" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENTS_REVIEW="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agents.merge" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENTS_MERGE="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agents.test" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENTS_TEST="$value"
    fi
    
    value="$(yaml_get "$config_file" ".agents.ci-fix" "")"
    if [[ -n "$value" ]]; then
        CONFIG_AGENTS_CI_FIX="$value"
    fi
    
    # improve_logs セクションのパース
    value="$(yaml_get "$config_file" ".improve_logs.keep_recent" "")"
    if [[ -n "$value" ]]; then
        CONFIG_IMPROVE_LOGS_KEEP_RECENT="$value"
    fi
    
    value="$(yaml_get "$config_file" ".improve_logs.keep_days" "")"
    if [[ -n "$value" ]]; then
        CONFIG_IMPROVE_LOGS_KEEP_DAYS="$value"
    fi
    
    value="$(yaml_get "$config_file" ".improve_logs.dir" "")"
    if [[ -n "$value" ]]; then
        CONFIG_IMPROVE_LOGS_DIR="$value"
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
    
    # agent.args
    local agent_args_list=""
    while IFS= read -r item; do
        if [[ -n "$item" ]]; then
            if [[ -z "$agent_args_list" ]]; then
                agent_args_list="$item"
            else
                agent_args_list="$agent_args_list $item"
            fi
        fi
    done < <(yaml_get_array "$config_file" ".agent.args")
    
    if [[ -n "$agent_args_list" ]]; then
        CONFIG_AGENT_ARGS="$agent_args_list"
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
    if [[ -n "${PI_RUNNER_MULTIPLEXER_TYPE:-}" ]]; then
        CONFIG_MULTIPLEXER_TYPE="$PI_RUNNER_MULTIPLEXER_TYPE"
    fi
    if [[ -n "${PI_RUNNER_MULTIPLEXER_SESSION_PREFIX:-}" ]]; then
        CONFIG_MULTIPLEXER_SESSION_PREFIX="$PI_RUNNER_MULTIPLEXER_SESSION_PREFIX"
    fi
    if [[ -n "${PI_RUNNER_MULTIPLEXER_START_IN_SESSION:-}" ]]; then
        CONFIG_MULTIPLEXER_START_IN_SESSION="$PI_RUNNER_MULTIPLEXER_START_IN_SESSION"
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
    if [[ -n "${PI_RUNNER_PLANS_KEEP_RECENT:-}" ]]; then
        CONFIG_PLANS_KEEP_RECENT="$PI_RUNNER_PLANS_KEEP_RECENT"
    fi
    if [[ -n "${PI_RUNNER_PLANS_DIR:-}" ]]; then
        CONFIG_PLANS_DIR="$PI_RUNNER_PLANS_DIR"
    fi
    if [[ -n "${PI_RUNNER_GITHUB_INCLUDE_COMMENTS:-}" ]]; then
        CONFIG_GITHUB_INCLUDE_COMMENTS="$PI_RUNNER_GITHUB_INCLUDE_COMMENTS"
    fi
    if [[ -n "${PI_RUNNER_GITHUB_MAX_COMMENTS:-}" ]]; then
        CONFIG_GITHUB_MAX_COMMENTS="$PI_RUNNER_GITHUB_MAX_COMMENTS"
    fi
    # エージェント設定の環境変数オーバーライド
    if [[ -n "${PI_RUNNER_AGENT_TYPE:-}" ]]; then
        CONFIG_AGENT_TYPE="$PI_RUNNER_AGENT_TYPE"
    fi
    if [[ -n "${PI_RUNNER_AGENT_COMMAND:-}" ]]; then
        CONFIG_AGENT_COMMAND="$PI_RUNNER_AGENT_COMMAND"
    fi
    if [[ -n "${PI_RUNNER_AGENT_ARGS:-}" ]]; then
        CONFIG_AGENT_ARGS="$PI_RUNNER_AGENT_ARGS"
    fi
    if [[ -n "${PI_RUNNER_AGENT_TEMPLATE:-}" ]]; then
        CONFIG_AGENT_TEMPLATE="$PI_RUNNER_AGENT_TEMPLATE"
    fi
    
    # agents セクションの環境変数オーバーライド
    if [[ -n "${PI_RUNNER_AGENTS_PLAN:-}" ]]; then
        CONFIG_AGENTS_PLAN="$PI_RUNNER_AGENTS_PLAN"
    fi
    if [[ -n "${PI_RUNNER_AGENTS_IMPLEMENT:-}" ]]; then
        CONFIG_AGENTS_IMPLEMENT="$PI_RUNNER_AGENTS_IMPLEMENT"
    fi
    if [[ -n "${PI_RUNNER_AGENTS_REVIEW:-}" ]]; then
        CONFIG_AGENTS_REVIEW="$PI_RUNNER_AGENTS_REVIEW"
    fi
    if [[ -n "${PI_RUNNER_AGENTS_MERGE:-}" ]]; then
        CONFIG_AGENTS_MERGE="$PI_RUNNER_AGENTS_MERGE"
    fi
    if [[ -n "${PI_RUNNER_AGENTS_TEST:-}" ]]; then
        CONFIG_AGENTS_TEST="$PI_RUNNER_AGENTS_TEST"
    fi
    if [[ -n "${PI_RUNNER_AGENTS_CI_FIX:-}" ]]; then
        CONFIG_AGENTS_CI_FIX="$PI_RUNNER_AGENTS_CI_FIX"
    fi
    
    # improve_logs セクションの環境変数オーバーライド
    if [[ -n "${PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT:-}" ]]; then
        CONFIG_IMPROVE_LOGS_KEEP_RECENT="$PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT"
    fi
    if [[ -n "${PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS:-}" ]]; then
        CONFIG_IMPROVE_LOGS_KEEP_DAYS="$PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS"
    fi
    if [[ -n "${PI_RUNNER_IMPROVE_LOGS_DIR:-}" ]]; then
        CONFIG_IMPROVE_LOGS_DIR="$PI_RUNNER_IMPROVE_LOGS_DIR"
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
        tmux_session_prefix|multiplexer_session_prefix|session_prefix)
            echo "$CONFIG_MULTIPLEXER_SESSION_PREFIX"
            ;;
        tmux_start_in_session|multiplexer_start_in_session|start_in_session)
            echo "$CONFIG_MULTIPLEXER_START_IN_SESSION"
            ;;
        multiplexer_type)
            echo "$CONFIG_MULTIPLEXER_TYPE"
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
        plans_keep_recent)
            echo "$CONFIG_PLANS_KEEP_RECENT"
            ;;
        plans_dir)
            echo "$CONFIG_PLANS_DIR"
            ;;
        github_include_comments)
            echo "$CONFIG_GITHUB_INCLUDE_COMMENTS"
            ;;
        github_max_comments)
            echo "$CONFIG_GITHUB_MAX_COMMENTS"
            ;;
        agent_type)
            echo "$CONFIG_AGENT_TYPE"
            ;;
        agent_command)
            echo "$CONFIG_AGENT_COMMAND"
            ;;
        agent_args)
            echo "$CONFIG_AGENT_ARGS"
            ;;
        agent_template)
            echo "$CONFIG_AGENT_TEMPLATE"
            ;;
        agents_plan)
            echo "$CONFIG_AGENTS_PLAN"
            ;;
        agents_implement)
            echo "$CONFIG_AGENTS_IMPLEMENT"
            ;;
        agents_review)
            echo "$CONFIG_AGENTS_REVIEW"
            ;;
        agents_merge)
            echo "$CONFIG_AGENTS_MERGE"
            ;;
        agents_test)
            echo "$CONFIG_AGENTS_TEST"
            ;;
        agents_ci_fix)
            echo "$CONFIG_AGENTS_CI_FIX"
            ;;
        improve_logs_keep_recent)
            echo "$CONFIG_IMPROVE_LOGS_KEEP_RECENT"
            ;;
        improve_logs_keep_days)
            echo "$CONFIG_IMPROVE_LOGS_KEEP_DAYS"
            ;;
        improve_logs_dir)
            echo "$CONFIG_IMPROVE_LOGS_DIR"
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
    echo "multiplexer_type: $CONFIG_MULTIPLEXER_TYPE"
    echo "multiplexer_session_prefix: $CONFIG_MULTIPLEXER_SESSION_PREFIX"
    echo "multiplexer_start_in_session: $CONFIG_MULTIPLEXER_START_IN_SESSION"
    echo "pi_command: $CONFIG_PI_COMMAND"
    echo "pi_args: $CONFIG_PI_ARGS"
    echo "parallel_max_concurrent: $CONFIG_PARALLEL_MAX_CONCURRENT"
    echo "plans_keep_recent: $CONFIG_PLANS_KEEP_RECENT"
    echo "plans_dir: $CONFIG_PLANS_DIR"
    echo "github_include_comments: $CONFIG_GITHUB_INCLUDE_COMMENTS"
    echo "github_max_comments: $CONFIG_GITHUB_MAX_COMMENTS"
    echo "agent_type: $CONFIG_AGENT_TYPE"
    echo "agent_command: $CONFIG_AGENT_COMMAND"
    echo "agent_args: $CONFIG_AGENT_ARGS"
    echo "agent_template: $CONFIG_AGENT_TEMPLATE"
    echo "agents_plan: $CONFIG_AGENTS_PLAN"
    echo "agents_implement: $CONFIG_AGENTS_IMPLEMENT"
    echo "agents_review: $CONFIG_AGENTS_REVIEW"
    echo "agents_merge: $CONFIG_AGENTS_MERGE"
    echo "agents_test: $CONFIG_AGENTS_TEST"
    echo "agents_ci_fix: $CONFIG_AGENTS_CI_FIX"
    echo "improve_logs_keep_recent: $CONFIG_IMPROVE_LOGS_KEEP_RECENT"
    echo "improve_logs_keep_days: $CONFIG_IMPROVE_LOGS_KEEP_DAYS"
    echo "improve_logs_dir: $CONFIG_IMPROVE_LOGS_DIR"
}
