#!/usr/bin/env bash
# multiplexer-zellij.sh - Zellij実装
#
# multiplexer.shから読み込まれる

set -euo pipefail

# Zellijがインストールされているか確認
mux_check() {
    if ! command -v zellij &> /dev/null; then
        log_error "zellij is not installed"
        log_info "Install with: brew install zellij"
        return 1
    fi
}

# セッション名を生成
mux_generate_session_name() {
    local issue_number="$1"
    
    load_config
    local prefix
    prefix="$(get_config session_prefix)"  # 同じ設定を使用
    
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
    
    log_info "Creating zellij session: $session_name"
    log_debug "Working directory: $working_dir"
    log_debug "Command: $command"
    
    # Zellijをバックグラウンドで起動
    # nohup + script でPTYを確保しつつバックグラウンド実行
    # サブシェルで実行して現在のディレクトリを変更しない
    (
        cd "$working_dir"
        nohup script -q /dev/null zellij -s "$session_name" </dev/null >/dev/null 2>&1 &
    )
    
    # セッションが作成されるまで待機
    local waited=0
    local max_wait=10
    while ! mux_session_exists "$session_name" && [[ "$waited" -lt "$max_wait" ]]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    
    if ! mux_session_exists "$session_name"; then
        log_error "Failed to create session: $session_name"
        return 1
    fi
    
    # 少し待ってからコマンドを送信
    sleep 1
    
    # ESCキーを送信してwelcome画面を閉じる
    ZELLIJ_SESSION_NAME="$session_name" zellij action write 27 2>/dev/null || true
    sleep 0.5
    
    # 環境変数を設定
    mux_send_keys "$session_name" "export GIT_EDITOR=true EDITOR=true VISUAL=true"
    sleep 0.3
    
    # 作業ディレクトリに移動
    mux_send_keys "$session_name" "cd '$working_dir'"
    sleep 0.3
    
    # コマンドを実行
    mux_send_keys "$session_name" "$command"
    
    log_info "Session created: $session_name"
}

# セッションが存在するか確認
mux_session_exists() {
    local session_name="$1"
    # ANSIエスケープコードを除去してから検索
    zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$session_name "
}

# セッションにアタッチ
mux_attach_session() {
    local session_name="$1"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    zellij attach "$session_name"
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
    
    zellij kill-session "$session_name" 2>/dev/null || true
    
    # 終了を待機
    local waited=0
    while mux_session_exists "$session_name" && [[ "$waited" -lt "$max_wait" ]]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    
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
    prefix="$(get_config session_prefix)"
    
    # Zellijのlist-sessionsの出力から名前を抽出
    zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}' | grep "^${prefix}" || true
}

# セッションの状態を取得
mux_get_session_info() {
    local session_name="$1"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        echo "Status: Not running"
        return 1
    fi
    
    # Zellijのセッション情報を取得
    local info
    info=$(zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep "^$session_name" || true)
    
    if [[ -n "$info" ]]; then
        echo "Name: $session_name, Info: $info"
    else
        echo "Name: $session_name"
    fi
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
    
    # Zellijはdump-screenでファイルに出力する必要がある
    local tmp_file
    tmp_file=$(mktemp)
    
    # セッションにアクションを送信
    ZELLIJ_SESSION_NAME="$session_name" zellij action dump-screen --full "$tmp_file" 2>/dev/null || {
        rm -f "$tmp_file"
        log_warn "Could not capture output from session: $session_name"
        return 1
    }
    
    # 最後のN行を表示
    tail -n "$lines" "$tmp_file" 2>/dev/null || true
    rm -f "$tmp_file"
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

# キーを送信
mux_send_keys() {
    local session_name="$1"
    local keys="$2"
    
    mux_check || return 1
    
    if ! mux_session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    # Zellijではwrite-charsでテキストを送信し、Enterを送る
    ZELLIJ_SESSION_NAME="$session_name" zellij action write-chars "$keys" 2>/dev/null || true
    # Enterキーを送信（改行コード）
    ZELLIJ_SESSION_NAME="$session_name" zellij action write 13 2>/dev/null || true
}
