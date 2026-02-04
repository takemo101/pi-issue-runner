#!/usr/bin/env bash
# agent.sh - エージェント実行ロジック
# 複数のコーディングエージェント（pi, Claude Code, OpenCode等）に対応

set -euo pipefail

_AGENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_AGENT_LIB_DIR/config.sh"
source "$_AGENT_LIB_DIR/log.sh"

# ======================
# プリセット定義（Bash 3.x互換）
# ======================

# プリセット情報を取得
# 引数:
#   $1 - preset_name: プリセット名 (pi | claude | opencode)
#   $2 - key: 取得するキー (command | prompt_style | template)
# 出力: 対応する値
get_agent_preset() {
    local preset_name="$1"
    local key="$2"
    
    case "$preset_name" in
        pi)
            case "$key" in
                command)
                    echo "pi"
                    ;;
                prompt_style)
                    echo "@file"
                    ;;
                template)
                    echo '{{command}} {{args}} @"{{prompt_file}}"'
                    ;;
            esac
            ;;
        claude)
            case "$key" in
                command)
                    echo "claude"
                    ;;
                prompt_style)
                    echo "print"
                    ;;
                template)
                    echo '{{command}} {{args}} --print "{{prompt_file}}"'
                    ;;
            esac
            ;;
        opencode)
            case "$key" in
                command)
                    echo "opencode"
                    ;;
                prompt_style)
                    echo "stdin"
                    ;;
                template)
                    echo 'cat "{{prompt_file}}" | {{command}} {{args}}'
                    ;;
            esac
            ;;
        *)
            echo ""
            ;;
    esac
}

# プリセットが存在するか確認
# 引数:
#   $1 - preset_name: プリセット名
# 戻り値: 0=存在する, 1=存在しない
preset_exists() {
    local preset_name="$1"
    
    case "$preset_name" in
        pi|claude|opencode)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ======================
# エージェント設定取得
# ======================

# エージェントタイプを取得
# 設定の優先順位:
#   1. agent.type が設定されている場合、それを使用
#   2. agent セクションがない場合、"pi" にフォールバック
get_agent_type() {
    local agent_type
    agent_type="$(get_config agent_type)"
    
    if [[ -n "$agent_type" ]]; then
        echo "$agent_type"
    else
        # フォールバック: デフォルトは "pi"
        echo "pi"
    fi
}

# エージェントコマンドを取得
# 設定の優先順位:
#   1. agent.command が設定されている場合、それを使用
#   2. agent.type が明示的に設定されている場合、プリセットを使用
#   3. pi.command にフォールバック
get_agent_command() {
    local agent_command
    agent_command="$(get_config agent_command)"
    
    if [[ -n "$agent_command" ]]; then
        echo "$agent_command"
    else
        # agent.type が明示的に設定されているかチェック
        local agent_type_config
        agent_type_config="$(get_config agent_type)"
        
        if [[ -n "$agent_type_config" ]]; then
            # agent.type が明示的に設定されている場合、プリセットを使用
            if [[ "$agent_type_config" != "custom" ]] && preset_exists "$agent_type_config"; then
                get_agent_preset "$agent_type_config" "command"
            else
                # custom タイプだが command が未設定の場合、pi.command にフォールバック
                get_config pi_command
            fi
        else
            # agent.type が未設定の場合、pi.command にフォールバック
            get_config pi_command
        fi
    fi
}

# エージェントの追加引数を取得
# 設定の優先順位:
#   1. agent.args が設定されている場合、それを使用
#   2. pi.args にフォールバック
get_agent_args() {
    local agent_args
    agent_args="$(get_config agent_args)"
    
    if [[ -n "$agent_args" ]]; then
        echo "$agent_args"
    else
        # フォールバック: pi.args
        get_config pi_args
    fi
}

# エージェントのテンプレートを取得
# 設定の優先順位:
#   1. agent.template が設定されている場合、それを使用
#   2. agent.type が明示的に設定されている場合、プリセットを使用
#   3. pi プリセットにフォールバック（後方互換性）
get_agent_template() {
    local agent_template
    agent_template="$(get_config agent_template)"
    
    if [[ -n "$agent_template" ]]; then
        echo "$agent_template"
    else
        # agent.type が明示的に設定されているかチェック
        local agent_type_config
        agent_type_config="$(get_config agent_type)"
        
        if [[ -n "$agent_type_config" ]] && preset_exists "$agent_type_config"; then
            get_agent_preset "$agent_type_config" "template"
        else
            # agent.type が未設定または不明な場合、pi プリセットにフォールバック
            get_agent_preset "pi" "template"
        fi
    fi
}

# ======================
# コマンド生成関数
# ======================

# テンプレート変数を置換
# 引数:
#   $1 - template: テンプレート文字列
#   $2 - command: コマンド
#   $3 - args: 引数
#   $4 - prompt_file: プロンプトファイルパス
# 出力: 置換後の文字列
_substitute_template() {
    local template="$1"
    local command="$2"
    local args="$3"
    local prompt_file="$4"
    
    local result="$template"
    result="${result//\{\{command\}\}/$command}"
    result="${result//\{\{args\}\}/$args}"
    result="${result//\{\{prompt_file\}\}/$prompt_file}"
    
    echo "$result"
}

# エージェント実行コマンドを構築
# 引数:
#   $1 - prompt_file: プロンプトファイルのパス
#   $2 - extra_args: 追加の引数（オプション）
# 出力: 実行コマンド文字列
build_agent_command() {
    local prompt_file="$1"
    local extra_args="${2:-}"
    
    local command
    command="$(get_agent_command)"
    
    local args
    args="$(get_agent_args)"
    
    # extra_args を追加
    if [[ -n "$extra_args" ]]; then
        if [[ -n "$args" ]]; then
            args="$args $extra_args"
        else
            args="$extra_args"
        fi
    fi
    
    local template
    template="$(get_agent_template)"
    
    local full_command
    full_command="$(_substitute_template "$template" "$command" "$args" "$prompt_file")"
    
    log_debug "Agent type: $(get_agent_type)"
    log_debug "Agent command: $command"
    log_debug "Agent args: $args"
    log_debug "Agent template: $template"
    log_debug "Full command: $full_command"
    
    echo "$full_command"
}

# ======================
# ユーティリティ関数
# ======================

# NOTE: 将来のCLIオプション追加やデバッグ用途のため保持
# 使用例: scripts/run.sh --list-presets

# 利用可能なプリセット一覧を表示
list_agent_presets() {
    echo "Available agent presets:"
    echo "  pi       - Pi coding agent (@file syntax)"
    echo "  claude   - Claude Code (--print option)"
    echo "  opencode - OpenCode (stdin)"
    echo "  custom   - Custom agent (requires template)"
}

# NOTE: 将来のCLIオプション追加やデバッグ用途のため保持
# 使用例: scripts/run.sh --show-config

# エージェント設定を表示（デバッグ用）
show_agent_config() {
    echo "=== Agent Configuration ==="
    echo "type: $(get_agent_type)"
    echo "command: $(get_agent_command)"
    echo "args: $(get_agent_args)"
    echo "template: $(get_agent_template)"
}
