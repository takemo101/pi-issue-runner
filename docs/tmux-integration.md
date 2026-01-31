# Tmux統合

## 概要

Tmuxセッションを使用して、各タスクを独立した仮想ターミナル内で実行します。これにより、バックグラウンド実行、アタッチ/デタッチ、出力のキャプチャが可能になります。

## Tmuxとは

Tmux (Terminal Multiplexer) は、1つのターミナルウィンドウで複数のセッションを管理できるツールです。セッションはバックグラウンドで実行され、必要に応じてアタッチ/デタッチできます。

### Pi Issue Runnerでの利用

- 各Issue = 1つのTmuxセッション
- セッション内でpiプロセスを実行
- バックグラウンドで複数タスクを並列実行可能

## セッション管理フロー

```
1. Issue番号を受け取る（例: 42）
   ↓
2. セッション名を生成（pi-issue-42）
   ↓
3. Worktreeを作成
   ↓
4. Tmuxセッションを作成（デタッチ状態）
   tmux new-session -s {session} -d -c {worktree}
   ↓
5. セッション内でpiコマンドを実行
   tmux send-keys -t {session} "pi '@.pi-prompt.md'" Enter
   ↓
6. watch-session.shで状態を監視
   ↓
7. タスク完了後、クリーンアップ
```

## lib/tmux.sh API

### セッション名生成

```bash
# Issue番号からセッション名を生成
session_name="$(generate_session_name 42)"
# → "pi-issue-42"

# セッション名からIssue番号を抽出
issue_number="$(extract_issue_number "pi-issue-42")"
# → "42"
```

**実装**:

```bash
generate_session_name() {
    local issue_number="$1"
    
    load_config
    local prefix
    prefix="$(get_config tmux_session_prefix)"  # デフォルト: "pi"
    
    if [[ "$prefix" == *"-issue" ]]; then
        echo "${prefix}-${issue_number}"
    else
        echo "${prefix}-issue-${issue_number}"
    fi
}
```

### セッション作成

```bash
# セッションを作成してコマンドを実行
create_session "pi-issue-42" "/path/to/worktree" "pi '@.pi-prompt.md'"
```

**実装**:

```bash
create_session() {
    local session_name="$1"
    local working_dir="$2"
    local command="$3"
    
    # Tmuxが利用可能か確認
    check_tmux || return 1
    
    # 既存セッションチェック
    if session_exists "$session_name"; then
        log_error "Session already exists: $session_name"
        return 1
    fi
    
    log_info "Creating tmux session: $session_name"
    
    # デタッチ状態でセッション作成
    tmux new-session -d -s "$session_name" -c "$working_dir"
    
    # コマンドを実行
    tmux send-keys -t "$session_name" "$command" Enter
    
    log_info "Session created: $session_name"
}
```

### セッション存在確認

```bash
if session_exists "pi-issue-42"; then
    echo "セッションは実行中です"
fi
```

**実装**:

```bash
session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}
```

### セッションにアタッチ

```bash
attach_session "pi-issue-42"
```

**実装**:

```bash
attach_session() {
    local session_name="$1"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    tmux attach-session -t "$session_name"
}
```

### セッション終了

```bash
kill_session "pi-issue-42"
```

**実装**:

```bash
kill_session() {
    local session_name="$1"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        log_warn "Session not found: $session_name"
        return 0
    fi
    
    log_info "Killing session: $session_name"
    tmux kill-session -t "$session_name"
}
```

### セッション一覧

```bash
# プレフィックスに一致するセッション一覧
list_sessions
# 出力:
# pi-issue-42
# pi-issue-43
```

**実装**:

```bash
list_sessions() {
    check_tmux || return 1
    
    load_config
    local prefix
    prefix="$(get_config tmux_session_prefix)"
    
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${prefix}" || true
}
```

### セッション出力キャプチャ

```bash
# 最新50行を取得
output="$(get_session_output "pi-issue-42" 50)"
```

**実装**:

```bash
get_session_output() {
    local session_name="$1"
    local lines="${2:-50}"
    
    check_tmux || return 1
    
    if ! session_exists "$session_name"; then
        log_error "Session not found: $session_name"
        return 1
    fi
    
    tmux capture-pane -t "$session_name" -p -S "-$lines"
}
```

### アクティブセッション数

```bash
count="$(count_active_sessions)"
echo "現在 $count セッションが実行中"
```

### 並列実行制限チェック

```bash
if ! check_concurrent_limit; then
    echo "最大同時実行数に達しています"
    exit 1
fi
```

## scripts/attach.sh

ユーザー向けのセッションアタッチスクリプト:

```bash
# Issue番号でアタッチ
./scripts/attach.sh 42

# セッション名でアタッチ
./scripts/attach.sh pi-issue-42
```

## scripts/watch-session.sh

### 概要

セッションの完了を監視するバックグラウンドプロセス。`run.sh` から自動的に起動されます。

### 監視内容

1. **セッション存在確認**: セッションが終了していないか
2. **完了マーカー検出**: `###TASK_COMPLETE_xxx###` パターン
3. **エラーマーカー検出**: `###TASK_ERROR_xxx###` パターン

### 処理フロー

```bash
# 主要ロジック（簡略化）
monitor_loop() {
    local session_name="$1"
    local issue_number
    issue_number="$(extract_issue_number "$session_name")"
    
    while true; do
        # セッション存在確認
        if ! session_exists "$session_name"; then
            handle_session_ended
            break
        fi
        
        # 出力をキャプチャ
        local output
        output="$(get_session_output "$session_name" 100)"
        
        # 完了マーカーをチェック
        if echo "$output" | grep -q "###TASK_COMPLETE_${issue_number}###"; then
            set_status "$issue_number" "complete"
            cleanup_session "$session_name"
            break
        fi
        
        # エラーマーカーをチェック
        if echo "$output" | grep -qE "###TASK_ERROR_${issue_number}###"; then
            local error_msg
            error_msg="$(extract_error_message "$output")"
            set_status "$issue_number" "error" "$error_msg"
            cleanup_session "$session_name"
            break
        fi
        
        sleep 5  # 5秒間隔
    done
}
```

### クリーンアップ処理

完了またはエラー検出時:

```bash
cleanup_session() {
    local session_name="$1"
    local issue_number
    issue_number="$(extract_issue_number "$session_name")"
    
    # Tmuxセッションを終了
    kill_session "$session_name"
    
    # Worktreeを削除
    local worktree
    if worktree="$(find_worktree_by_issue "$issue_number")"; then
        remove_worktree "$worktree" true
    fi
    
    log_info "Cleanup completed for session: $session_name"
}
```

## Tmuxコマンドリファレンス

### よく使うコマンド

```bash
# セッション一覧
tmux list-sessions

# セッションにアタッチ
tmux attach -t pi-issue-42

# セッションからデタッチ
# Ctrl+b d

# セッション終了
tmux kill-session -t pi-issue-42

# ペイン出力をキャプチャ
tmux capture-pane -t pi-issue-42 -p -S -100
```

### セッション作成オプション

```bash
# 基本的な作成（デタッチ状態）
tmux new-session -s session-name -d

# 作業ディレクトリを指定
tmux new-session -s session-name -d -c /path/to/dir

# 作成後すぐにアタッチ
tmux new-session -s session-name -c /path/to/dir
```

### コマンド送信

```bash
# コマンドを送信
tmux send-keys -t session-name "command" Enter

# Ctrl+Cを送信（中断）
tmux send-keys -t session-name C-c
```

## エラーハンドリング

### Tmuxが利用できない場合

```bash
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        log_error "tmux is not installed"
        return 1
    fi
}
```

### セッションが既に存在する場合

`run.sh` での処理:

```bash
if session_exists "$session_name"; then
    if [[ "$reattach" == "true" ]]; then
        # 既存セッションにアタッチ
        attach_session "$session_name"
        exit 0
    elif [[ "$force" == "true" ]]; then
        # 既存セッションを削除して再作成
        kill_session "$session_name"
    else
        log_error "Session already exists: $session_name"
        log_info "Options:"
        log_info "  --reattach  Attach to existing session"
        log_info "  --force     Remove and recreate session"
        exit 1
    fi
fi
```

### セッション終了の検出

`watch-session.sh` でのセッション消失検出:

```bash
if ! session_exists "$session_name"; then
    # セッションが予期せず終了
    log_warn "Session $session_name has ended unexpectedly"
    set_status "$issue_number" "error" "Session unexpectedly terminated"
    break
fi
```

## 設定

### .pi-runner.yaml

```yaml
tmux:
  session_prefix: "pi"           # セッション名プレフィックス
  start_in_session: true         # セッション作成後に自動アタッチ
```

### 環境変数

```bash
PI_RUNNER_TMUX_SESSION_PREFIX="my-prefix"
PI_RUNNER_TMUX_START_IN_SESSION="false"
```

## トラブルシューティング

### 問題: "tmux: command not found"

**解決**:
```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt-get install tmux
```

### 問題: セッションにアタッチできない

**原因**: セッションが別のクライアントにアタッチ済み

**解決**:
```bash
# 強制的にアタッチ（他のクライアントをデタッチ）
tmux attach -t pi-issue-42 -d
```

### 問題: セッションが残っている

**解決**:
```bash
# 手動で終了
tmux kill-session -t pi-issue-42

# またはスクリプトで
./scripts/stop.sh 42
```

### 問題: 出力が文字化けする

**原因**: ロケール設定の問題

**解決**:
```bash
# 環境変数を設定
export LANG=en_US.UTF-8
```

## ベストプラクティス

1. **セッション命名**
   - プレフィックスを統一（デフォルト: `pi`）
   - Issue番号を含める

2. **バックグラウンド実行**
   - `--no-attach` オプションで非対話的に起動
   - `watch-session.sh` で監視

3. **リソース管理**
   - `parallel_max_concurrent` で同時実行数を制限
   - 定期的に `list.sh` でセッションを確認

4. **クリーンアップ**
   - 完了マーカーで自動クリーンアップ
   - 手動終了は `stop.sh` または `cleanup.sh` を使用

5. **デバッグ**
   - `attach.sh` でセッションにアタッチして状況確認
   - `capture-pane` で出力を取得
