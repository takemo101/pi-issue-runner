#!/usr/bin/env bash
# workflow-selector.sh - ワークフロー自動選択（auto モード）
#
# Issue のタイトル・本文から最適なワークフローを選択する。
# 1. AI（pi --print）で選択を試行
# 2. ルールベースでフォールバック
# 3. 最終フォールバック: default

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_WORKFLOW_SELECTOR_SH_SOURCED:-}" ]]; then
    return 0
fi
_WORKFLOW_SELECTOR_SH_SOURCED="true"

_WORKFLOW_SELECTOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 依存ライブラリ（workflow.sh 経由で既にロード済みの場合はスキップ）
if ! declare -f log_info &> /dev/null; then
    source "$_WORKFLOW_SELECTOR_LIB_DIR/log.sh"
fi
if ! declare -f get_all_workflows_info &> /dev/null; then
    source "$_WORKFLOW_SELECTOR_LIB_DIR/workflow-loader.sh"
fi
if ! declare -f get_config &> /dev/null; then
    source "$_WORKFLOW_SELECTOR_LIB_DIR/config.sh"
fi

# ===================
# メイン関数
# ===================

# auto モードでワークフローを選択
# Usage: resolve_auto_workflow_name <issue_title> <issue_body> [project_root]
# Returns: 選択されたワークフロー名（stdout）
resolve_auto_workflow_name() {
    local issue_title="$1"
    local issue_body="${2:-}"
    local project_root="${3:-.}"

    # 利用可能なワークフロー情報を取得
    local workflows_info
    workflows_info=$(get_all_workflows_info "$project_root")

    if [[ -z "$workflows_info" ]]; then
        echo "default"
        return 0
    fi

    # ワークフロー名リスト（検証用）
    local valid_names
    valid_names=$(echo "$workflows_info" | cut -f1)

    # 1. AI で選択を試行
    local selected=""
    selected=$(_select_workflow_by_ai "$issue_title" "$issue_body" "$workflows_info" 2>/dev/null) || true

    if [[ -n "$selected" ]] && echo "$valid_names" | grep -qx "$selected"; then
        echo "$selected"
        return 0
    fi

    # 2. ルールベースフォールバック
    selected=$(_select_workflow_by_rules "$issue_title" "$valid_names") || true

    if [[ -n "$selected" ]]; then
        echo "$selected"
        return 0
    fi

    # 3. 最終フォールバック
    echo "default"
}

# ===================
# AI 選択
# ===================

# pi --print を使ってワークフローを選択
_select_workflow_by_ai() {
    local issue_title="$1"
    local issue_body="$2"
    local workflows_info="$3"

    # pi コマンドの存在確認
    local pi_command="${PI_COMMAND:-pi}"
    if ! command -v "$pi_command" &> /dev/null; then
        return 1
    fi

    # エージェント設定から provider と model を取得
    local provider model
    provider=$(_get_ai_provider)
    model=$(_get_ai_model)

    # ワークフロー名と説明の一覧テキスト
    local workflows_text=""
    while IFS=$'\t' read -r name description _steps _context; do
        if [[ -n "$name" ]]; then
            workflows_text+="- ${name}: ${description}"$'\n'
        fi
    done < <(echo "$workflows_info")

    # Issue本文は先頭500文字のみ（トークン節約）
    local body_snippet="${issue_body:0:500}"

    # 選択プロンプト
    local prompt
    prompt="Select the most appropriate workflow name for this GitHub Issue.
Reply with ONLY the workflow name (a single word, no explanation, no punctuation).

Issue Title: ${issue_title}
Issue Description (excerpt): ${body_snippet}

Available Workflows:
${workflows_text}
Workflow name:"

    # pi --print で非対話実行（タイムアウト15秒）
    local response
    response=$(echo "$prompt" | timeout 15 "$pi_command" --print \
        --provider "$provider" \
        --model "$model" \
        --no-tools \
        --no-session 2>/dev/null) || return 1

    # レスポンスからワークフロー名を抽出（空白・改行除去、小文字化）
    local result
    result=$(echo "$response" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi

    return 1
}

# エージェント設定から provider を取得
_get_ai_provider() {
    # 1. .pi-runner.yaml の auto.provider
    if declare -f get_config &> /dev/null; then
        load_config 2>/dev/null || true
        local config_provider
        config_provider=$(get_config auto_provider 2>/dev/null || true)
        if [[ -n "$config_provider" ]]; then
            echo "$config_provider"
            return 0
        fi

        # 2. agent.args の --provider から推定
        local args
        args=$(get_config agent_args 2>/dev/null || true)
        if [[ "$args" =~ --provider[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi

    # 3. デフォルト
    echo "anthropic"
}

# auto 選択用のモデルを取得（軽量モデル推奨）
_get_ai_model() {
    # 1. .pi-runner.yaml の auto.model
    if declare -f get_config &> /dev/null; then
        load_config 2>/dev/null || true
        local config_model
        config_model=$(get_config auto_model 2>/dev/null || true)
        if [[ -n "$config_model" ]]; then
            echo "$config_model"
            return 0
        fi
    fi

    # 2. デフォルト（高速・安価なモデル）
    echo "claude-haiku-4-5-20250218"
}

# ===================
# ルールベース選択
# ===================

# Issue タイトルのプレフィックスからワークフローを推定
_select_workflow_by_rules() {
    local issue_title="$1"
    local valid_names="$2"

    # タイトルを小文字に変換
    local lower_title
    lower_title=$(echo "$issue_title" | tr '[:upper:]' '[:lower:]')

    local selected=""

    # プレフィックスパターンで判定
    case "$lower_title" in
        feat:*|feat\(*|feature:*)
            selected="feature" ;;
        fix:*|fix\(*|bug:*|bug\(*|refactor:*|refactor\(*|security:*|security\(*)
            selected="fix" ;;
        docs:*|docs\(*|doc:*|doc\(*)
            selected="docs" ;;
        test:*|test\(*|tests:*)
            selected="test" ;;
        chore:*|chore\(*|typo:*|style:*|style\(*)
            selected="quickfix" ;;
    esac

    # 選択されたワークフローが有効か検証
    if [[ -n "$selected" ]] && echo "$valid_names" | grep -qx "$selected"; then
        echo "$selected"
        return 0
    fi

    return 1
}
