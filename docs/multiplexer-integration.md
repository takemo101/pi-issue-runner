# マルチプレクサ統合

## 概要

ターミナルマルチプレクサを使用して、各タスクを独立した仮想ターミナル内で実行します。これにより、バックグラウンド実行、アタッチ/デタッチ、出力のキャプチャが可能になります。

Pi Issue Runnerは **tmux** と **Zellij** の両方をサポートしており、設定で切り替えることができます。

## マルチプレクサとは

ターミナルマルチプレクサは、1つのターミナルウィンドウで複数のセッションを管理できるツールです。セッションはバックグラウンドで実行され、必要に応じてアタッチ/デタッチできます。

### Pi Issue Runnerでの利用

- 各Issue = 1つのセッション
- セッション内でpiプロセスを実行
- バックグラウンドで複数タスクを並列実行可能
- セッションへのアタッチで進捗確認

## マルチプレクサの選択

### 設定ファイル

`.pi-runner.yaml` で使用するマルチプレクサを指定します：

```yaml
multiplexer:
  # tmux または zellij
  type: tmux
  session_prefix: pi
  start_in_session: true
```

**Zellijを使用する場合**:

```yaml
multiplexer:
  type: zellij
  session_prefix: pi
  start_in_session: true
```

### 環境変数

一時的に切り替える場合は環境変数を使用します：

```bash
# Zellijを一時的に使用
PI_RUNNER_MULTIPLEXER_TYPE=zellij ./scripts/run.sh 42

# Tmuxを一時的に使用
PI_RUNNER_MULTIPLEXER_TYPE=tmux ./scripts/run.sh 42
```

## セッション管理フロー

マルチプレクサに関係なく、共通のフローで動作します：

```
1. Issue番号を受け取る（例: 42）
   ↓
2. セッション名を生成（pi-issue-42）
   ↓
3. Worktreeを作成
   ↓
4. セッションを作成（デタッチ状態）
   ↓
5. セッション内でpiコマンドを実行
   ↓
6. watch-session.shで状態を監視
   ↓
7. タスク完了後、クリーンアップ
```

## lib/multiplexer.sh API

### 共通インターフェース

マルチプレクサに依存しない共通のAPI：

```bash
# マルチプレクサのタイプを取得
mux_type="$(get_multiplexer_type)"
# → "tmux" または "zellij"

# セッション名を生成
session_name="$(mux_generate_session_name 42)"
# → "pi-issue-42"

# セッション名からIssue番号を抽出
issue_number="$(mux_extract_issue_number "pi-issue-42")"
# → "42"

# セッションを作成
mux_create_session "pi-issue-42" "/path/to/worktree" "pi '@.pi-prompt.md'"

# セッション存在確認
if mux_session_exists "pi-issue-42"; then
    echo "セッションは実行中です"
fi

# セッションにアタッチ
mux_attach_session "pi-issue-42"

# セッション終了
mux_kill_session "pi-issue-42"

# セッション一覧
mux_list_sessions

# セッション出力キャプチャ
output="$(mux_get_session_output "pi-issue-42" 50)"

# アクティブセッション数
count="$(mux_count_active_sessions)"
```

---

## Tmux

### Tmuxとは

Tmux (Terminal Multiplexer) は、広く使われているターミナルマルチプレクサです。安定性と豊富な機能で知られています。

### インストール

```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt-get install tmux

# Arch Linux
sudo pacman -S tmux
```

### Tmux固有の実装

#### セッション作成

```bash
# デタッチ状態でセッション作成
tmux new-session -d -s "$session_name" -c "$working_dir"

# コマンドを実行
tmux send-keys -t "$session_name" "$command" Enter
```

#### セッション存在確認

```bash
tmux has-session -t "$session_name" 2>/dev/null
```

#### ペイン出力のキャプチャ

```bash
# 最新50行を取得
tmux capture-pane -t "$session_name" -p -S -50
```

### Tmuxコマンドリファレンス

```bash
# セッション一覧
tmux list-sessions
tmux ls

# セッションにアタッチ
tmux attach -t pi-issue-42
tmux a -t pi-issue-42

# セッションからデタッチ
# Ctrl+b d

# セッション終了
tmux kill-session -t pi-issue-42

# ペイン出力をキャプチャ
tmux capture-pane -t pi-issue-42 -p -S -100

# コマンドを送信
tmux send-keys -t pi-issue-42 "command" Enter

# Ctrl+Cを送信（中断）
tmux send-keys -t pi-issue-42 C-c
```

### Tmux設定例

`.pi-runner.yaml`:

```yaml
multiplexer:
  type: tmux
  session_prefix: pi
  start_in_session: true
```

---

## Zellij

### Zellijとは

Zellij は Rust で書かれた現代的なターミナルマルチプレクサです。直感的なUIと優れたデフォルト設定が特徴です。

#### Tmuxとの主な違い

- **UI**: より視覚的で初心者にも分かりやすい
- **設定**: より少ない設定で使い始められる
- **プラグインシステム**: WASM ベースのプラグインをサポート
- **言語**: Rust で実装され、高速で安定

### インストール

```bash
# macOS
brew install zellij

# Cargo（Rust）
cargo install zellij

# Linux（バイナリ）
# https://github.com/zellij-org/zellij/releases
```

### Zellij固有の実装

#### セッション作成

Zellijはバックグラウンド実行のために `script` コマンドを使用します：

```bash
# PTYを確保してバックグラウンドで起動
(
    cd "$working_dir"
    nohup script -q /dev/null zellij -s "$session_name" </dev/null >/dev/null 2>&1 &
)

# セッションが作成されるまで待機
while ! mux_session_exists "$session_name"; do
    sleep 0.5
done
```

#### セッション存在確認

```bash
# ANSIエスケープコードを除去して検索
zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^$session_name "
```

#### 出力のキャプチャ

Zellijは `dump-screen` アクションでファイルに出力します：

```bash
# 一時ファイルに出力
tmp_file=$(mktemp)
ZELLIJ_SESSION_NAME="$session_name" zellij action dump-screen --full "$tmp_file"

# 内容を表示
cat "$tmp_file"
rm -f "$tmp_file"
```

#### キー送信

```bash
# テキストを送信
ZELLIJ_SESSION_NAME="$session_name" zellij action write-chars "command"

# Enterキーを送信（ASCII 13）
ZELLIJ_SESSION_NAME="$session_name" zellij action write 13
```

### Zellijコマンドリファレンス

```bash
# セッション一覧
zellij list-sessions
zellij ls

# セッションにアタッチ
zellij attach pi-issue-42
zellij a pi-issue-42

# セッションからデタッチ
# Ctrl+o d

# セッション終了
zellij delete-session pi-issue-42 --force
zellij kill-session pi-issue-42

# セッションの出力をファイルに保存
ZELLIJ_SESSION_NAME=pi-issue-42 zellij action dump-screen output.txt

# コマンドを送信
ZELLIJ_SESSION_NAME=pi-issue-42 zellij action write-chars "command"
ZELLIJ_SESSION_NAME=pi-issue-42 zellij action write 13  # Enter
```

### Zellij設定例

`.pi-runner.yaml`:

```yaml
multiplexer:
  type: zellij
  session_prefix: pi
  start_in_session: true
```

### TmuxからZellijへの移行

既にTmuxを使用している場合、Zellijへの移行は簡単です：

1. **設定を変更**:
   ```yaml
   multiplexer:
     type: zellij  # tmux → zellij
   ```

2. **Tmuxセッションをクリーンアップ**:
   ```bash
   # Tmuxセッションを全て終了
   ./scripts/cleanup.sh --all
   ```

3. **Zellijで新しいタスクを開始**:
   ```bash
   ./scripts/run.sh 42
   ```

### キーバインドの違い

| 操作 | Tmux | Zellij |
|------|------|--------|
| プレフィックス | `Ctrl+b` | `Ctrl+o` |
| デタッチ | `Ctrl+b d` | `Ctrl+o d` |
| ペイン分割（縦） | `Ctrl+b %` | `Ctrl+o "` |
| ペイン分割（横） | `Ctrl+b "` | `Ctrl+o '` |
| ヘルプ | `Ctrl+b ?` | `Ctrl+o ?` |

---

## scripts/attach.sh

両方のマルチプレクサに対応したアタッチスクリプト：

```bash
# Issue番号でアタッチ
./scripts/attach.sh 42

# セッション名でアタッチ
./scripts/attach.sh pi-issue-42
```

内部的に `mux_attach_session` を使用するため、設定されているマルチプレクサが自動的に使用されます。

## scripts/watch-session.sh

### 概要

セッションの完了を監視するバックグラウンドプロセス。`run.sh` から自動的に起動されます。

### 監視内容

1. **セッション存在確認**: セッションが終了していないか
2. **完了マーカー検出**: `###TASK_COMPLETE_xxx###` パターン
3. **エラーマーカー検出**: `###TASK_ERROR_xxx###` パターン

### マルチプレクサ非依存

`watch-session.sh` は `mux_session_exists` と `mux_get_session_output` を使用するため、どちらのマルチプレクサでも動作します。

### 処理フロー

```bash
# 主要ロジック（簡略化）
monitor_loop() {
    local session_name="$1"
    local issue_number
    issue_number="$(mux_extract_issue_number "$session_name")"
    
    while true; do
        # セッション存在確認（マルチプレクサ非依存）
        if ! mux_session_exists "$session_name"; then
            handle_session_ended
            break
        fi
        
        # 出力をキャプチャ（マルチプレクサ非依存）
        local output
        output="$(mux_get_session_output "$session_name" 100)"
        
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

完了またはエラー検出時、マルチプレクサに関係なくクリーンアップが実行されます：

```bash
cleanup_session() {
    local session_name="$1"
    local issue_number
    issue_number="$(mux_extract_issue_number "$session_name")"
    
    # セッションを終了（マルチプレクサ非依存）
    mux_kill_session "$session_name"
    
    # Worktreeを削除
    local worktree
    if worktree="$(find_worktree_by_issue "$issue_number")"; then
        remove_worktree "$worktree" true
    fi
    
    log_info "Cleanup completed for session: $session_name"
}
```

## エラーハンドリング

### マルチプレクサが利用できない場合

```bash
mux_check() {
    # 各実装で定義
    if ! command -v <multiplexer> &> /dev/null; then
        log_error "<multiplexer> is not installed"
        return 1
    fi
}
```

使用前に必ず `mux_check` が呼ばれます。

### セッションが既に存在する場合

`run.sh` での処理：

```bash
if mux_session_exists "$session_name"; then
    if [[ "$reattach" == "true" ]]; then
        # 既存セッションにアタッチ
        mux_attach_session "$session_name"
        exit 0
    elif [[ "$force" == "true" ]]; then
        # 既存セッションを削除して再作成
        mux_kill_session "$session_name"
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

`watch-session.sh` でのセッション消失検出：

```bash
if ! mux_session_exists "$session_name"; then
    # セッションが予期せず終了
    log_warn "Session $session_name has ended unexpectedly"
    set_status "$issue_number" "error" "Session unexpectedly terminated"
    break
fi
```

## 設定

### .pi-runner.yaml

```yaml
multiplexer:
  type: tmux              # または zellij
  session_prefix: "pi"    # セッション名プレフィックス
  start_in_session: true  # セッション作成後に自動アタッチ

parallel:
  max_concurrent: 5       # 最大同時セッション数
```

### 環境変数

| 環境変数 | 設定キー | デフォルト |
|----------|----------|-----------|
| `PI_RUNNER_MULTIPLEXER_TYPE` | `multiplexer.type` | `tmux` |
| `PI_RUNNER_MULTIPLEXER_SESSION_PREFIX` | `multiplexer.session_prefix` | `pi` |
| `PI_RUNNER_MULTIPLEXER_START_IN_SESSION` | `multiplexer.start_in_session` | `true` |

## トラブルシューティング

### Tmux

#### 問題: "tmux: command not found"

**解決**:
```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt-get install tmux
```

#### 問題: セッションにアタッチできない

**原因**: セッションが別のクライアントにアタッチ済み

**解決**:
```bash
# 強制的にアタッチ（他のクライアントをデタッチ）
tmux attach -t pi-issue-42 -d
```

#### 問題: 出力が文字化けする

**原因**: ロケール設定の問題

**解決**:
```bash
# 環境変数を設定
export LANG=en_US.UTF-8
```

### Zellij

#### 問題: "zellij: command not found"

**解決**:
```bash
# macOS
brew install zellij

# Cargo
cargo install zellij
```

#### 問題: セッションが作成されない

**原因**: `script` コマンドが利用できない

**解決**:
```bash
# macOS（通常はプリインストール済み）
# Linux
sudo apt-get install util-linux  # Debian/Ubuntu
```

#### 問題: 出力のキャプチャに失敗する

**原因**: セッションがアクティブでない

**解決**:
```bash
# セッションが実行中か確認
zellij list-sessions

# セッションを再起動
./scripts/stop.sh 42
./scripts/run.sh 42
```

#### 問題: キー送信が反映されない

**原因**: Zellijセッションが初期化中

**解決**:
- `mux_create_session` は自動的に待機します
- 手動で送信する場合は `sleep 2` を追加

### 共通

#### 問題: セッションが残っている

**解決**:
```bash
# 手動で終了
./scripts/stop.sh 42

# 全セッションをクリーンアップ
./scripts/cleanup.sh --all
```

#### 問題: 最大同時実行数に達した

**解決**:
```bash
# 現在のセッション一覧を確認
./scripts/list.sh

# 不要なセッションを終了
./scripts/stop.sh <issue_number>

# または最大数を増やす
# .pi-runner.yaml
parallel:
  max_concurrent: 10
```

## ベストプラクティス

1. **マルチプレクサの選択**
   - 初心者: Zellij（UIが分かりやすい）
   - 経験者/既存環境: Tmux（広く使われている）
   - 性能重視: どちらも高速（大きな差はない）

2. **セッション命名**
   - プレフィックスを統一（デフォルト: `pi`）
   - Issue番号を含める（自動的に行われる）

3. **バックグラウンド実行**
   - `--no-attach` オプションで非対話的に起動
   - `watch-session.sh` が自動監視

4. **リソース管理**
   - `parallel.max_concurrent` で同時実行数を制限
   - 定期的に `list.sh` でセッションを確認
   - 不要なセッションは `stop.sh` で終了

5. **クリーンアップ**
   - 完了マーカーで自動クリーンアップ
   - 手動終了は `stop.sh` または `cleanup.sh` を使用
   - `cleanup.sh --all` で全セッションを削除

6. **デバッグ**
   - `attach.sh` でセッションにアタッチして状況確認
   - `mux_get_session_output` で出力を取得
   - `DEBUG=1` 環境変数で詳細ログを有効化

7. **移行**
   - TmuxとZellijは簡単に切り替え可能
   - 既存セッションをクリーンアップしてから切り替え
   - 設定ファイルまたは環境変数で制御

## 参考資料

- [Tmux公式サイト](https://github.com/tmux/tmux)
- [Tmux Cheat Sheet](https://tmuxcheatsheet.com/)
- [Zellij公式サイト](https://zellij.dev/)
- [Zellij GitHub](https://github.com/zellij-org/zellij)
- [lib/multiplexer.sh](../lib/multiplexer.sh) - API定義
- [lib/multiplexer-tmux.sh](../lib/multiplexer-tmux.sh) - Tmux実装
- [lib/multiplexer-zellij.sh](../lib/multiplexer-zellij.sh) - Zellij実装
