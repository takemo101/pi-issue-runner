#!/usr/bin/env bash
# tmux.sh - マルチプレクサ操作（公式API）
#
# このファイルはマルチプレクサ操作の公式APIを提供します。
# 内部実装は lib/multiplexer.sh によって提供されています。
#
# 設定で multiplexer.type を変更することで、
# tmux または zellij を使用できます。

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_TMUX_SH_SOURCED:-}" ]]; then
    return 0
fi
_TMUX_SH_SOURCED="true"

_TMUX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# multiplexer.sh をロード（これが実際の実装を提供）
source "$_TMUX_LIB_DIR/multiplexer.sh"

# ============================================================================
# 後方互換性のためのエイリアス関数
# 既存のスクリプトはこれらの関数名を使用しています
# ============================================================================

# マルチプレクサがインストールされているか確認
check_tmux() {
    mux_check
}

# セッション名を生成
generate_session_name() {
    mux_generate_session_name "$@"
}

# セッション名からIssue番号を抽出
extract_issue_number() {
    mux_extract_issue_number "$@"
}

# セッションを作成してコマンドを実行
create_session() {
    mux_create_session "$@"
}

# セッションが存在するか確認
session_exists() {
    mux_session_exists "$@"
}

# セッションにアタッチ
attach_session() {
    mux_attach_session "$@"
}

# セッションを終了
kill_session() {
    mux_kill_session "$@"
}

# セッション一覧を取得
list_sessions() {
    mux_list_sessions
}

# セッションの状態を取得
get_session_info() {
    mux_get_session_info "$@"
}

# セッションのペインの内容を取得（最新N行）
get_session_output() {
    mux_get_session_output "$@"
}

# アクティブなセッション数をカウント
count_active_sessions() {
    mux_count_active_sessions
}

# 並列実行数の制限をチェック
check_concurrent_limit() {
    mux_check_concurrent_limit
}

# キーを送信
send_keys() {
    mux_send_keys "$@"
}
