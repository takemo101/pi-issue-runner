#!/usr/bin/env bash
# tmux.sh - 後方互換ラッパー（非推奨）
#
# ⚠️ DEPRECATED: このファイルは後方互換性のために残されています。
# 新しいコードでは lib/multiplexer.sh を直接使用してください。
#
# 移行ガイド:
#   source lib/tmux.sh       → source lib/multiplexer.sh
#   check_tmux               → mux_check
#   generate_session_name    → mux_generate_session_name
#   extract_issue_number     → mux_extract_issue_number
#   create_session           → mux_create_session
#   session_exists           → mux_session_exists
#   attach_session           → mux_attach_session
#   kill_session             → mux_kill_session
#   list_sessions            → mux_list_sessions
#   get_session_info         → mux_get_session_info
#   get_session_output       → mux_get_session_output
#   count_active_sessions    → mux_count_active_sessions
#   check_concurrent_limit   → mux_check_concurrent_limit
#   send_keys                → mux_send_keys

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
# 後方互換性のためのエイリアス関数（非推奨）
# 外部ツールやプラグインが使用している可能性があるため残しています
# ============================================================================

check_tmux() { mux_check; }
generate_session_name() { mux_generate_session_name "$@"; }
extract_issue_number() { mux_extract_issue_number "$@"; }
create_session() { mux_create_session "$@"; }
session_exists() { mux_session_exists "$@"; }
attach_session() { mux_attach_session "$@"; }
kill_session() { mux_kill_session "$@"; }
list_sessions() { mux_list_sessions; }
get_session_info() { mux_get_session_info "$@"; }
get_session_output() { mux_get_session_output "$@"; }
count_active_sessions() { mux_count_active_sessions; }
check_concurrent_limit() { mux_check_concurrent_limit; }
send_keys() { mux_send_keys "$@"; }
