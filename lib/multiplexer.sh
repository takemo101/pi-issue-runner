#!/usr/bin/env bash
# multiplexer.sh - マルチプレクサ抽象化レイヤー
#
# tmuxとZellijの両方をサポートする共通インターフェース

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_MULTIPLEXER_SH_SOURCED:-}" ]]; then
    return 0
fi
_MULTIPLEXER_SH_SOURCED="true"

_MUX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_MUX_LIB_DIR/config.sh"
source "$_MUX_LIB_DIR/log.sh"

# 現在のマルチプレクサタイプをキャッシュ
_MUX_TYPE=""

# マルチプレクサタイプを取得
get_multiplexer_type() {
    if [[ -n "$_MUX_TYPE" ]]; then
        echo "$_MUX_TYPE"
        return
    fi
    
    load_config
    _MUX_TYPE="$(get_config multiplexer_type)"
    
    # デフォルトはtmux
    if [[ -z "$_MUX_TYPE" ]]; then
        _MUX_TYPE="tmux"
    fi
    
    echo "$_MUX_TYPE"
}

# 実装をロード
_load_multiplexer_impl() {
    local mux_type
    mux_type="$(get_multiplexer_type)"
    
    case "$mux_type" in
        tmux)
            source "$_MUX_LIB_DIR/multiplexer-tmux.sh"
            ;;
        zellij)
            source "$_MUX_LIB_DIR/multiplexer-zellij.sh"
            ;;
        *)
            log_error "Unknown multiplexer type: $mux_type"
            log_info "Supported types: tmux, zellij"
            return 1
            ;;
    esac
}

# 実装をロード
_load_multiplexer_impl

# ============================================================================
# 共通インターフェース
# 以下の関数は各実装ファイルで定義される
# ============================================================================

# mux_check              - マルチプレクサがインストールされているか確認
# mux_generate_session_name <issue_number> - セッション名を生成
# mux_extract_issue_number <session_name>  - セッション名からIssue番号を抽出
# mux_create_session <name> <working_dir> <command> - セッション作成
# mux_session_exists <name>                - セッション存在確認
# mux_attach_session <name>                - セッションにアタッチ
# mux_kill_session <name> [max_wait]       - セッション終了
# mux_list_sessions                        - セッション一覧
# mux_get_session_info <name>              - セッション情報取得
# mux_get_session_output <name> [lines]    - セッション出力取得
# mux_count_active_sessions                - アクティブセッション数
# mux_check_concurrent_limit               - 並列実行制限チェック
# mux_send_keys <name> <keys>              - キー送信
