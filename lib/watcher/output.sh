#!/usr/bin/env bash
# ============================================================================
# lib/watcher/output.sh - Output logging functions for watch-session
#
# Responsibilities:
#   - Setup pipe-pane output logging (setup_output_logging)
#   - Stop output logging (stop_output_logging)
#   - Clean up output log files (cleanup_output_log)
#   - Capture baseline output (capture_baseline)
# ============================================================================

set -euo pipefail

# Source required libraries
WATCHER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../log.sh
source "$WATCHER_LIB_DIR/../log.sh"
# shellcheck source=../config.sh
source "$WATCHER_LIB_DIR/../config.sh"
# shellcheck source=../multiplexer.sh
source "$WATCHER_LIB_DIR/../multiplexer.sh"

# ============================================================================
# Setup pipe-pane output logging for reliable marker detection
# Usage: setup_output_logging <session_name> <issue_number>
# Output: path to log file (empty if pipe-pane is not available)
# ============================================================================
setup_output_logging() {
    local session_name="$1"
    local issue_number="$2"
    
    # tmuxのpipe-paneが使えるか確認
    local mux_type
    mux_type="$(get_multiplexer_type 2>/dev/null)" || mux_type="tmux"
    
    if [[ "$mux_type" != "tmux" ]]; then
        log_info "pipe-pane not available for $mux_type, using capture-pane fallback"
        echo ""
        return
    fi
    
    # ログディレクトリ
    local status_dir
    status_dir="$(get_status_dir)"
    local log_file="${status_dir}/output-${issue_number}.log"
    
    # 既存のpipe-paneを閉じてから新規設定
    tmux pipe-pane -t "$session_name" "" 2>/dev/null || true
    
    # pipe-paneでセッション出力をファイルに追記
    # Note: ベースラインキャプチャ後に開始するため、初期出力は含まれない。
    #       初期マーカーチェックはベースラインキャプチャで対応済み。
    # ANSIエスケープシーケンスとCR(\r)を除去してからファイルに書き込む。
    # pipe-paneは生のターミナル出力（カラーコード等）を含むため、
    # 除去しないとマーカーの完全一致検出に失敗する（Issue #1210）。
    # perlを使用: macOS の sed は不正バイトシーケンスで "illegal byte sequence" エラーになる。
    # ターミナル出力にはUTF-8として不正なバイトが含まれることがあり、
    # sed (UTF-8モード) では処理できない。perlはバイナリセーフ。
    local pipe_cmd="perl -pe 's/\e\][^\a\e]*(?:\a|\e\\\\)//g; s/\e\[[0-9;?]*[a-zA-Z]//g; s/\r//g' >> '${log_file}'"
    if tmux pipe-pane -t "$session_name" "$pipe_cmd" 2>/dev/null; then
        # pipe-paneコマンドをtmuxセッション環境変数に保存
        # （mux_send_keys の paste-buffer 時の再接続用）
        tmux set-environment -t "$session_name" MUX_PIPE_CMD "$pipe_cmd" 2>/dev/null || true
        log_info "Output logging started: $log_file"
        echo "$log_file"
    else
        log_warn "Failed to start pipe-pane, using capture-pane fallback"
        echo ""
    fi
}

# ============================================================================
# Stop pipe-pane output logging
# Usage: stop_output_logging <session_name> <output_log>
# ============================================================================
stop_output_logging() {
    local session_name="$1"
    local output_log="$2"
    
    if [[ -n "$output_log" ]]; then
        tmux pipe-pane -t "$session_name" "" 2>/dev/null || true
        log_debug "Output logging stopped"
    fi
}

# ============================================================================
# Clean up output log file
# Usage: cleanup_output_log <output_log>
# ============================================================================
cleanup_output_log() {
    local output_log="$1"
    
    if [[ -n "$output_log" && -f "$output_log" ]]; then
        rm -f "$output_log"
        log_debug "Output log cleaned up: $output_log"
    fi
}

# ============================================================================
# Capture baseline output and wait for initial prompt display
# Usage: capture_baseline <session_name>
# Output: baseline output text via stdout
# ============================================================================
capture_baseline() {
    local session_name="$1"

    # 初期遅延（プロンプト表示を待つ）
    local initial_delay
    initial_delay="$(get_config watcher_initial_delay)"
    log_info "Waiting for initial prompt display (${initial_delay}s)..."
    sleep "$initial_delay"

    # 初期出力をキャプチャ（ベースライン）
    mux_get_session_output "$session_name" 1000 2>/dev/null || echo ""
}

# Export functions for use by watch-session.sh
export -f setup_output_logging
export -f stop_output_logging
export -f cleanup_output_log
export -f capture_baseline
