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
# 形式: {prefix}-issue-{number} (例: pi-issue-42)
generate_session_name() {
    local issue_number="$1"
    
    load_config
    local prefix
    prefix="$(get_config tmux_session_prefix)"
    # prefixに既に"-issue"が含まれている場合は追加しない
    if [[ "$prefix" == *"-issue" ]]; then
        echo "${prefix}-${issue_number}"
    else
        echo "${prefix}-issue-${issue_number}"
    fi
}

# セッション名からIssue番号を抽出
# 例: "pi-issue-42" -> "42", "pi-issue-42-feature" -> "42"
extract_issue_number() {
    local session_name="$1"
    
    # パターン: -issue-{数字} を探す
    if [[ "$session_name" =~ -issue-([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # フォールバック: 最後のハイフン以降の数字
    if [[ "$session_name" =~ -([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # さらにフォールバック: 最初に見つかる数字列
    if [[ "$session_name" =~ ([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    echo ""
    return 1
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

# アクティブなセッション数をカウント
count_active_sessions() {
    local count
    count="$(list_sessions | wc -l | tr -d ' ')"
    echo "$count"
}

# 並列実行数の制限をチェック
# 戻り値: 0=OK, 1=制限超過
check_concurrent_limit() {
    load_config
    local max_concurrent
    max_concurrent="$(get_config parallel_max_concurrent)"
    
    # 0または空は無制限
    if [[ -z "$max_concurrent" || "$max_concurrent" == "0" ]]; then
        return 0
    fi
    
    local current_count
    current_count="$(count_active_sessions)"
    
    if [[ "$current_count" -ge "$max_concurrent" ]]; then
        echo "Error: Maximum concurrent sessions ($max_concurrent) reached." >&2
        echo "Currently running ($current_count sessions):" >&2
        list_sessions | sed 's/^/  - /' >&2
        echo "" >&2
        echo "Use --force to override or cleanup existing sessions." >&2
        return 1
    fi
    
    return 0
}
