#!/usr/bin/env bash
# tmux.sh - tmux操作

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# tmuxがインストールされているか確認
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        echo "Error: tmux is not installed" >&2
        return 1
    fi
}

# セッション名を生成
generate_session_name() {
    local issue_number="$1"
    
    load_config
    echo "$(get_config tmux_session_prefix)-$issue_number"
}

# セッションを作成してコマンドを実行
create_session() {
    local session_name="$1"
    local working_dir="$2"
    local command="$3"
    
    check_tmux || return 1
    
    if session_exists "$session_name"; then
        echo "Error: Session already exists: $session_name" >&2
        return 1
    fi
    
    echo "Creating tmux session: $session_name"
    echo "Working directory: $working_dir"
    echo "Command: $command"
    
    # デタッチ状態でセッション作成
    tmux new-session -d -s "$session_name" -c "$working_dir"
    
    # コマンドを送信
    tmux send-keys -t "$session_name" "$command" Enter
    
    echo "Session created: $session_name"
}

# セッションが存在するか確認
session_exists() {
    local session_name="$1"
    
    tmux has-session -t "$session_name" 2>/dev/null
}

# セッションにアタッチ
attach_session() {
    local session_name="$1"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        echo "Error: Session not found: $session_name" >&2
        return 1
    fi
    
    tmux attach-session -t "$session_name"
}

# セッションを終了
kill_session() {
    local session_name="$1"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        echo "Warning: Session not found: $session_name" >&2
        return 0
    fi
    
    echo "Killing session: $session_name"
    tmux kill-session -t "$session_name"
}

# セッション一覧を取得
list_sessions() {
    check_tmux || return 1
    
    load_config
    local prefix
    prefix="$(get_config tmux_session_prefix)"
    
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${prefix}" || true
}

# セッションの状態を取得
get_session_info() {
    local session_name="$1"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        echo "Status: Not running"
        return 1
    fi
    
    tmux list-sessions -F "Name: #{session_name}, Created: #{session_created}, Windows: #{session_windows}" \
        | grep "^Name: $session_name"
}

# セッションのペインの内容を取得（最新N行）
get_session_output() {
    local session_name="$1"
    local lines="${2:-50}"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        echo "Error: Session not found: $session_name" >&2
        return 1
    fi
    
    tmux capture-pane -t "$session_name" -p -S "-$lines"
}
