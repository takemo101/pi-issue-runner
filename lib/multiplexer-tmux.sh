#!/usr/bin/env bash
# multiplexer-tmux.sh - tmux実装
#
# multiplexer.shから読み込まれる

set -euo pipefail

# ソースガード（多重読み込み防止）
if [[ -n "${_MULTIPLEXER_TMUX_SH_SOURCED:-}" ]]; then
    return 0
fi
_MULTIPLEXER_TMUX_SH_SOURCED="true"

# tmuxがインストールされているか確認
mux_check() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux is not installed"
        return 1
    fi
}

# セッション名を生成
mux_generate_session_name() {
    local issue_number="$1"
    
    load_config
    local prefix
    prefix="$(get_config multiplexer_session_prefix)"
    
    if [[ "$prefix" == *"-issue" ]]; then
        echo "${prefix}-${issue_number}"
    else
        echo "${prefix}-issue-${issue_number}"
    fi
}

# セッション名からIssue番号を抽出
mux_extract_issue_number() {
    local session_name="$1"
    
    if [[ "$session_name" =~ -issue-([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    if [[ "$session_name" =~ -([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    if [[ "$session_name" =~ ([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    echo ""
    return 1
}

# セッションを作成してコマンドを実行
mux_create_session() {
    local session_name="$1"
    local working_dir="$2"
    local command="$3"
    
    mux_check || return 1
    
    if mux_session_exists "$session_name"; then
        log_error "Session already exists: $session_name"
        return 1
    fi
    
    log_info "Creating tmux session: $session_name"
    log_debug "Working directory: $working_dir"
    log_debug "Command: $command"
    
    # デタッチ状態でセッション作成
    tmux new-session -d -s "$session_name" -c "$working_dir"
    
    # マウススクロールを有効化
    tmux set-option -t "$session_name" mouse on 2>/dev/null || true
    
    # エディタを無効化
    tmux send-keys -t "$session_name" "export GIT_EDITOR=true EDITOR=true VISUAL=true" Enter
    
    # コマンドを実行
    tmux send-keys -t "$session_name" "$command" Enter
    
    log_info "Session created: $session_name"
}

# セッションが存在するか確認
mux_session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

# セッションにアタッチ
mux_attach_session() {
    local session_name="$1"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    tmux attach-session -t "$session_name"
}

# セッションを終了
mux_kill_session() {
    local session_name="$1"
    local max_wait="${2:-30}"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        log_warn "Session not found: $session_name"
        return 0
    fi
    
    log_info "Killing session: $session_name"
    
    # 安全なディレクトリに移動
    tmux send-keys -t "$session_name" "cd /tmp" Enter 2>/dev/null || true
    sleep 1
    
    # pane PIDを取得
    local pane_pids
    pane_pids=$(tmux list-panes -t "$session_name" -F '#{pane_pid}' 2>/dev/null || true)
    
    # セッションを終了
    tmux kill-session -t "$session_name" 2>/dev/null || true
    
    # 終了を待機
    local waited=0
    while mux_session_exists "$session_name" && [[ "$waited" -lt "$max_wait" ]]; do
        sleep 1
        waited=$((waited + 1))
    done
    
    # PIDベースでの追加確認
    if [[ -n "$pane_pids" ]]; then
        local pid_waited=0
        local pid_max_wait=10
        local any_running=true
        
        while [[ "$any_running" == "true" && "$pid_waited" -lt "$pid_max_wait" ]]; do
            any_running=false
            while IFS= read -r pid; do
                [[ -z "$pid" ]] && continue
                if kill -0 "$pid" 2>/dev/null; then
                    any_running=true
                    break
                fi
            done <<< "$pane_pids"
            
            if [[ "$any_running" == "true" ]]; then
                sleep 1
                pid_waited=$((pid_waited + 1))
            fi
        done
    fi
    
    if mux_session_exists "$session_name"; then
        log_warn "Session $session_name still exists after ${max_wait}s wait"
        return 1
    fi
    
    log_debug "Session $session_name terminated successfully"
    return 0
}

# セッション一覧を取得
mux_list_sessions() {
    mux_check || return 1
    
    load_config
    local prefix
    prefix="$(get_config multiplexer_session_prefix)"
    
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${prefix}" | grep -v "^${prefix}-monitor$" || true
}

# セッションの状態を取得
mux_get_session_info() {
    local session_name="$1"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        echo "Status: Not running"
        return 1
    fi
    
    tmux list-sessions -F "Name: #{session_name}, Created: #{session_created}, Windows: #{session_windows}" \
        | grep "^Name: $session_name"
}

# セッションの出力を取得
mux_get_session_output() {
    local session_name="$1"
    local lines="${2:-50}"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    tmux capture-pane -t "$session_name" -p -S "-$lines"
}

# アクティブなセッション数をカウント
mux_count_active_sessions() {
    local count
    count="$(mux_list_sessions | wc -l | tr -d ' ')"
    echo "$count"
}

# 並列実行数の制限をチェック
mux_check_concurrent_limit() {
    load_config
    local max_concurrent
    max_concurrent="$(get_config parallel_max_concurrent)"
    
    if [[ -z "$max_concurrent" || "$max_concurrent" == "0" ]]; then
        return 0
    fi
    
    local current_count
    current_count="$(mux_count_active_sessions)"
    
    if [[ "$current_count" -ge "$max_concurrent" ]]; then
        log_error "Maximum concurrent sessions ($max_concurrent) reached."
        log_info "Currently running ($current_count sessions):"
        mux_list_sessions | sed 's/^/  - /' >&2
        log_info "Use --force to override or cleanup existing sessions."
        return 1
    fi
    
    return 0
}

# paste-buffer 後に pipe-pane を再接続する
# tmux セッション環境変数 MUX_PIPE_CMD から保存された pipe-pane コマンドを読み込んで再設定する
_mux_reconnect_pipe_pane() {
    local session_name="$1"
    
    # tmux セッション環境変数から pipe-pane コマンドを取得
    local pipe_cmd
    pipe_cmd="$(tmux show-environment -t "$session_name" MUX_PIPE_CMD 2>/dev/null | sed 's/^MUX_PIPE_CMD=//')" || pipe_cmd=""
    
    if [[ -n "$pipe_cmd" ]]; then
        # ペースト内容がフラッシュされるのを待ってから再接続
        sleep 1
        tmux pipe-pane -t "$session_name" "$pipe_cmd" 2>/dev/null || {
            log_warn "Failed to reconnect pipe-pane for session: $session_name"
            return 1
        }
    else
        log_warn "No saved pipe-pane command for session: $session_name, pipe-pane not reconnected"
        return 1
    fi
}

# キーを送信
# 大きなテキスト（1024バイト超）は tmux load-buffer + paste-buffer を使用して
# "command too long" エラーを回避する
mux_send_keys() {
    local session_name="$1"
    local keys="$2"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    if [[ ${#keys} -gt 1024 ]]; then
        # 大きなテキストはファイル経由で送信（tmux send-keys の長さ制限を回避）
        local tmpfile
        tmpfile="$(mktemp "${TMPDIR:-/tmp}/mux-send-XXXXXX")"
        printf '%s' "$keys" > "$tmpfile"
        
        # pipe-pane を一時停止（ペースト内容がログに記録されるとマーカー誤検出の原因になる）
        local pipe_was_active=false
        if [[ "$(tmux list-panes -t "$session_name" -F '#{pane_pipe}' 2>/dev/null)" == "1" ]]; then
            pipe_was_active=true
            tmux pipe-pane -t "$session_name" "" 2>/dev/null || true
        fi
        
        if tmux load-buffer "$tmpfile" 2>/dev/null \
            && tmux paste-buffer -t "$session_name" 2>/dev/null; then
            tmux send-keys -t "$session_name" Enter
            local rc=$?
            # pipe-pane を再開（元のコマンドは不明なので、停止していた場合のみ再接続を試みる）
            if [[ "$pipe_was_active" == "true" ]]; then
                _mux_reconnect_pipe_pane "$session_name"
            fi
            rm -f "$tmpfile"
            return $rc
        else
            log_warn "load-buffer/paste-buffer failed, falling back to send-keys"
            # pipe-pane を再開
            if [[ "$pipe_was_active" == "true" ]]; then
                _mux_reconnect_pipe_pane "$session_name"
            fi
            rm -f "$tmpfile"
            tmux send-keys -t "$session_name" "$keys" Enter
        fi
    else
        tmux send-keys -t "$session_name" "$keys" Enter
    fi
}
