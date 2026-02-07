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
CONFIG_WORKTREE_BASE_BRANCH="${CONFIG_WORKTREE_BASE_BRANCH:-HEAD}"
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

# auto ワークフロー選択設定
CONFIG_AUTO_PROVIDER="${CONFIG_AUTO_PROVIDER:-}"    # auto選択用のAIプロバイダー（空 = agent設定から推定 or anthropic）
CONFIG_AUTO_MODEL="${CONFIG_AUTO_MODEL:-}"          # auto選択用のモデル（空 = claude-haiku-4-5）

# Hooks設定
CONFIG_HOOKS_ON_START="${CONFIG_HOOKS_ON_START:-}"       # セッション開始時のhook
CONFIG_HOOKS_ON_SUCCESS="${CONFIG_HOOKS_ON_SUCCESS:-}"   # セッション成功時のhook
CONFIG_HOOKS_ON_ERROR="${CONFIG_HOOKS_ON_ERROR:-}"       # セッションエラー時のhook
CONFIG_HOOKS_ON_CLEANUP="${CONFIG_HOOKS_ON_CLEANUP:-}"   # クリーンアップ時のhook
CONFIG_HOOKS_ON_IMPROVE_START="${CONFIG_HOOKS_ON_IMPROVE_START:-}"     # improve開始時のhook
CONFIG_HOOKS_ON_IMPROVE_END="${CONFIG_HOOKS_ON_IMPROVE_END:-}"         # improve終了時のhook
CONFIG_HOOKS_ON_ITERATION_START="${CONFIG_HOOKS_ON_ITERATION_START:-}" # イテレーション開始時のhook
CONFIG_HOOKS_ON_ITERATION_END="${CONFIG_HOOKS_ON_ITERATION_END:-}"     # イテレーション終了時のhook
CONFIG_HOOKS_ON_REVIEW_COMPLETE="${CONFIG_HOOKS_ON_REVIEW_COMPLETE:-}" # レビュー完了時のhook

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

# Configuration mapping table for simple key-value pairs
_CONFIG_SIMPLE_MAPPINGS=(
    ".worktree.base_dir:CONFIG_WORKTREE_BASE_DIR"
    ".worktree.base_branch:CONFIG_WORKTREE_BASE_BRANCH"
    ".multiplexer.type:CONFIG_MULTIPLEXER_TYPE"
    ".multiplexer.session_prefix:CONFIG_MULTIPLEXER_SESSION_PREFIX"
    ".multiplexer.start_in_session:CONFIG_MULTIPLEXER_START_IN_SESSION"
    ".pi.command:CONFIG_PI_COMMAND"
    ".parallel.max_concurrent:CONFIG_PARALLEL_MAX_CONCURRENT"
    ".plans.keep_recent:CONFIG_PLANS_KEEP_RECENT"
    ".plans.dir:CONFIG_PLANS_DIR"
    ".github.include_comments:CONFIG_GITHUB_INCLUDE_COMMENTS"
    ".github.max_comments:CONFIG_GITHUB_MAX_COMMENTS"
    ".agent.type:CONFIG_AGENT_TYPE"
    ".agent.command:CONFIG_AGENT_COMMAND"
    ".agent.template:CONFIG_AGENT_TEMPLATE"
    ".agents.plan:CONFIG_AGENTS_PLAN"
    ".agents.implement:CONFIG_AGENTS_IMPLEMENT"
    ".agents.review:CONFIG_AGENTS_REVIEW"
    ".agents.merge:CONFIG_AGENTS_MERGE"
    ".agents.test:CONFIG_AGENTS_TEST"
    ".agents.ci-fix:CONFIG_AGENTS_CI_FIX"
    ".auto.provider:CONFIG_AUTO_PROVIDER"
    ".auto.model:CONFIG_AUTO_MODEL"
    ".improve_logs.keep_recent:CONFIG_IMPROVE_LOGS_KEEP_RECENT"
    ".improve_logs.keep_days:CONFIG_IMPROVE_LOGS_KEEP_DAYS"
    ".improve_logs.dir:CONFIG_IMPROVE_LOGS_DIR"
    ".hooks.on_start:CONFIG_HOOKS_ON_START"
    ".hooks.on_success:CONFIG_HOOKS_ON_SUCCESS"
    ".hooks.on_error:CONFIG_HOOKS_ON_ERROR"
    ".hooks.on_cleanup:CONFIG_HOOKS_ON_CLEANUP"
    ".hooks.on_improve_start:CONFIG_HOOKS_ON_IMPROVE_START"
    ".hooks.on_improve_end:CONFIG_HOOKS_ON_IMPROVE_END"
    ".hooks.on_iteration_start:CONFIG_HOOKS_ON_ITERATION_START"
    ".hooks.on_iteration_end:CONFIG_HOOKS_ON_ITERATION_END"
    ".hooks.on_review_complete:CONFIG_HOOKS_ON_REVIEW_COMPLETE"
)

# Parse simple key-value configurations using mapping table
_parse_simple_configs() {
    local config_file="$1"
    local yaml_key var_name value
    
    for mapping in "${_CONFIG_SIMPLE_MAPPINGS[@]}"; do
        yaml_key="${mapping%%:*}"
        var_name="${mapping##*:}"
        value="$(yaml_get "$config_file" "$yaml_key" "")"
        if [[ -n "$value" ]]; then
            # Use printf -v instead of eval for safer variable assignment
            # This avoids code injection risks with special characters in values
            printf -v "$var_name" "%s" "$value"
        fi
    done
}

# 設定ファイルをパース（yaml.shを使用）
_parse_config_file() {
    local config_file="$1"
    
    # Parse all simple key-value configs using mapping table
    _parse_simple_configs "$config_file"
    
    # Parse array configs separately (different logic)
    _parse_array_configs "$config_file"
}

# YAML配列をスペース区切り文字列として変数に設定
# Usage: _load_array_config <config_file> <yaml_path> <config_var_name>
_load_array_config() {
    local config_file="$1"
    local yaml_path="$2"
    local var_name="$3"
    local result=""
    
    while IFS= read -r item; do
        if [[ -n "$item" ]]; then
            result="${result:+$result }$item"
        fi
    done < <(yaml_get_array "$config_file" "$yaml_path")
    
    if [[ -n "$result" ]]; then
        printf -v "$var_name" "%s" "$result"
    fi
}

# 配列設定をパース
_parse_array_configs() {
    local config_file="$1"
    
    _load_array_config "$config_file" ".worktree.copy_files" "CONFIG_WORKTREE_COPY_FILES"
    _load_array_config "$config_file" ".pi.args" "CONFIG_PI_ARGS"
    _load_array_config "$config_file" ".agent.args" "CONFIG_AGENT_ARGS"
}

# Environment variable to config variable mapping table
# Format: "ENV_SUFFIX:CONFIG_VAR_NAME"
_ENV_OVERRIDE_MAP=(
    "WORKTREE_BASE_DIR:CONFIG_WORKTREE_BASE_DIR"
    "WORKTREE_BASE_BRANCH:CONFIG_WORKTREE_BASE_BRANCH"
    "WORKTREE_COPY_FILES:CONFIG_WORKTREE_COPY_FILES"
    "MULTIPLEXER_TYPE:CONFIG_MULTIPLEXER_TYPE"
    "MULTIPLEXER_SESSION_PREFIX:CONFIG_MULTIPLEXER_SESSION_PREFIX"
    "MULTIPLEXER_START_IN_SESSION:CONFIG_MULTIPLEXER_START_IN_SESSION"
    "PI_COMMAND:CONFIG_PI_COMMAND"
    "PI_ARGS:CONFIG_PI_ARGS"
    "PARALLEL_MAX_CONCURRENT:CONFIG_PARALLEL_MAX_CONCURRENT"
    "PLANS_KEEP_RECENT:CONFIG_PLANS_KEEP_RECENT"
    "PLANS_DIR:CONFIG_PLANS_DIR"
    "GITHUB_INCLUDE_COMMENTS:CONFIG_GITHUB_INCLUDE_COMMENTS"
    "GITHUB_MAX_COMMENTS:CONFIG_GITHUB_MAX_COMMENTS"
    "AGENT_TYPE:CONFIG_AGENT_TYPE"
    "AGENT_COMMAND:CONFIG_AGENT_COMMAND"
    "AGENT_ARGS:CONFIG_AGENT_ARGS"
    "AGENT_TEMPLATE:CONFIG_AGENT_TEMPLATE"
    "AGENTS_PLAN:CONFIG_AGENTS_PLAN"
    "AGENTS_IMPLEMENT:CONFIG_AGENTS_IMPLEMENT"
    "AGENTS_REVIEW:CONFIG_AGENTS_REVIEW"
    "AGENTS_MERGE:CONFIG_AGENTS_MERGE"
    "AGENTS_TEST:CONFIG_AGENTS_TEST"
    "AGENTS_CI_FIX:CONFIG_AGENTS_CI_FIX"
    "IMPROVE_LOGS_KEEP_RECENT:CONFIG_IMPROVE_LOGS_KEEP_RECENT"
    "IMPROVE_LOGS_KEEP_DAYS:CONFIG_IMPROVE_LOGS_KEEP_DAYS"
    "IMPROVE_LOGS_DIR:CONFIG_IMPROVE_LOGS_DIR"
    "HOOKS_ON_START:CONFIG_HOOKS_ON_START"
    "HOOKS_ON_SUCCESS:CONFIG_HOOKS_ON_SUCCESS"
    "HOOKS_ON_ERROR:CONFIG_HOOKS_ON_ERROR"
    "HOOKS_ON_CLEANUP:CONFIG_HOOKS_ON_CLEANUP"
    "HOOKS_ON_IMPROVE_START:CONFIG_HOOKS_ON_IMPROVE_START"
    "HOOKS_ON_IMPROVE_END:CONFIG_HOOKS_ON_IMPROVE_END"
    "HOOKS_ON_ITERATION_START:CONFIG_HOOKS_ON_ITERATION_START"
    "HOOKS_ON_ITERATION_END:CONFIG_HOOKS_ON_ITERATION_END"
    "HOOKS_ON_REVIEW_COMPLETE:CONFIG_HOOKS_ON_REVIEW_COMPLETE"
)

# 環境変数による上書き（テーブル駆動）
_apply_env_overrides() {
    local entry env_var config_var value
    for entry in "${_ENV_OVERRIDE_MAP[@]}"; do
        env_var="PI_RUNNER_${entry%%:*}"
        config_var="${entry##*:}"
        value="${!env_var:-}"
        if [[ -n "$value" ]]; then
            # Use printf -v instead of eval for safer variable assignment
            # This avoids code injection risks with special characters in values
            printf -v "$config_var" "%s" "$value"
        fi
    done
}

# Configuration key to variable name mapping table
# Format: "config_key:CONFIG_VAR_NAME"
declare -A _CONFIG_KEY_MAP=(
    [worktree_base_dir]=CONFIG_WORKTREE_BASE_DIR
    [worktree_base_branch]=CONFIG_WORKTREE_BASE_BRANCH
    [worktree_copy_files]=CONFIG_WORKTREE_COPY_FILES
    [multiplexer_type]=CONFIG_MULTIPLEXER_TYPE
    [multiplexer_session_prefix]=CONFIG_MULTIPLEXER_SESSION_PREFIX
    [multiplexer_start_in_session]=CONFIG_MULTIPLEXER_START_IN_SESSION
    [pi_command]=CONFIG_PI_COMMAND
    [pi_args]=CONFIG_PI_ARGS
    [parallel_max_concurrent]=CONFIG_PARALLEL_MAX_CONCURRENT
    [plans_keep_recent]=CONFIG_PLANS_KEEP_RECENT
    [plans_dir]=CONFIG_PLANS_DIR
    [github_include_comments]=CONFIG_GITHUB_INCLUDE_COMMENTS
    [github_max_comments]=CONFIG_GITHUB_MAX_COMMENTS
    [agent_type]=CONFIG_AGENT_TYPE
    [agent_command]=CONFIG_AGENT_COMMAND
    [agent_args]=CONFIG_AGENT_ARGS
    [agent_template]=CONFIG_AGENT_TEMPLATE
    [agents_plan]=CONFIG_AGENTS_PLAN
    [agents_implement]=CONFIG_AGENTS_IMPLEMENT
    [agents_review]=CONFIG_AGENTS_REVIEW
    [agents_merge]=CONFIG_AGENTS_MERGE
    [agents_test]=CONFIG_AGENTS_TEST
    [agents_ci_fix]=CONFIG_AGENTS_CI_FIX
    [auto_provider]=CONFIG_AUTO_PROVIDER
    [auto_model]=CONFIG_AUTO_MODEL
    [improve_logs_keep_recent]=CONFIG_IMPROVE_LOGS_KEEP_RECENT
    [improve_logs_keep_days]=CONFIG_IMPROVE_LOGS_KEEP_DAYS
    [improve_logs_dir]=CONFIG_IMPROVE_LOGS_DIR
    [hooks_on_start]=CONFIG_HOOKS_ON_START
    [hooks_on_success]=CONFIG_HOOKS_ON_SUCCESS
    [hooks_on_error]=CONFIG_HOOKS_ON_ERROR
    [hooks_on_cleanup]=CONFIG_HOOKS_ON_CLEANUP
    [hooks_on_improve_start]=CONFIG_HOOKS_ON_IMPROVE_START
    [hooks_on_improve_end]=CONFIG_HOOKS_ON_IMPROVE_END
    [hooks_on_iteration_start]=CONFIG_HOOKS_ON_ITERATION_START
    [hooks_on_iteration_end]=CONFIG_HOOKS_ON_ITERATION_END
    [hooks_on_review_complete]=CONFIG_HOOKS_ON_REVIEW_COMPLETE
)

# Deprecated key aliases mapping
# Format: "deprecated_key:canonical_key"
declare -A _CONFIG_DEPRECATED_KEYS=(
    # @deprecated Use multiplexer_session_prefix instead of tmux_session_prefix
    [tmux_session_prefix]=multiplexer_session_prefix
    [session_prefix]=multiplexer_session_prefix
    # @deprecated Use multiplexer_start_in_session instead of tmux_start_in_session
    [tmux_start_in_session]=multiplexer_start_in_session
    [start_in_session]=multiplexer_start_in_session
)

# 設定値を取得（テーブル駆動）
get_config() {
    local key="$1"
    local canonical_key="$key"
    
    # Handle deprecated keys (temporarily disable nounset for array subscript access)
    set +u
    if [[ -n "${_CONFIG_DEPRECATED_KEYS[$key]:-}" ]]; then
        canonical_key="${_CONFIG_DEPRECATED_KEYS[$key]}"
    fi
    
    # Look up the variable name from the mapping table
    local var_name="${_CONFIG_KEY_MAP[$canonical_key]:-}"
    set -u
    
    if [[ -n "$var_name" ]]; then
        # Use indirect expansion to get the variable value
        echo "${!var_name}"
    else
        # Unknown key - return empty string
        echo ""
    fi
}

# 設定の再読み込み（テスト用）
reload_config() {
    _CONFIG_LOADED=""
    reset_yaml_cache
    load_config "$@"
}

# 設定を表示（デバッグ用、テーブル駆動）
show_config() {
    echo "=== Configuration ==="
    
    # Iterate over all config keys in sorted order (quote array subscript)
    local key var_name
    for key in $(printf '%s\n' "${!_CONFIG_KEY_MAP[@]}" | sort); do
        var_name="${_CONFIG_KEY_MAP["$key"]}"
        echo "$key: ${!var_name}"
    done
}
