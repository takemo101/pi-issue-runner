# 並列実行

## 概要

複数のGitHub Issueを同時に処理する機能です。各タスクは独立したworktreeとtmuxセッションで実行されるため、相互に干渉しません。

## アーキテクチャ

```
                     ┌────────────────────────────────┐
                     │   scripts/run.sh (並列起動)   │
                     │                                │
                     │  - check_concurrent_limit()   │
                     │  - セッション数制限            │
                     └────────────┬───────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
          ┌─────────▼─────────┐     ┌──────────▼──────────┐
          │  Tmux Session 1   │     │  Tmux Session 2     │
          │                   │     │                     │
          │ Issue #42         │     │ Issue #43           │
          │ ├─ Worktree       │     │ ├─ Worktree         │
          │ └─ Pi Process     │     │ └─ Pi Process       │
          └───────────────────┘     └─────────────────────┘
                   │                          │
          ┌────────▼────────┐     ┌───────────▼───────────┐
          │ watch-session.sh│     │  watch-session.sh    │
          │  (監視プロセス)  │     │   (監視プロセス)      │
          └─────────────────┘     └───────────────────────┘
```

## run-batch.sh の使用

`scripts/run-batch.sh` は複数Issueを依存関係を考慮して自動実行するスクリプトです。

### 基本的な使い方

```bash
# 複数Issueを一括実行（依存関係順に自動実行）
./scripts/run-batch.sh 42 43 44 45 46

# 実行計画のみ表示（実際には実行しない）
./scripts/run-batch.sh 42 43 44 --dry-run

# 順次実行（並列実行せず1つずつ実行）
./scripts/run-batch.sh 42 43 44 --sequential

# エラーがあっても次のレイヤーを継続実行
./scripts/run-batch.sh 42 43 44 --continue-on-error

# タイムアウト指定（デフォルト: 3600秒）
./scripts/run-batch.sh 42 43 44 --timeout 1800

# 詳細ログを出力
./scripts/run-batch.sh 42 43 44 -v
```

### 依存関係の解析

`run-batch.sh` はGitHubの "Blocked by" 関係を解析し、依存関係に基づいて実行レイヤーを計算します。

**実行例**:

```
Issue #42 ──→ Issue #44 ──→ Issue #46
Issue #43 ──→ Issue #45
```

この場合、以下のレイヤーで実行されます：

```
Layer 0: #42, #43 (依存なし、並列実行)
Layer 1: #44, #45 (Layer 0完了後、並列実行)
Layer 2: #46 (Layer 1完了後)
```

### オプション一覧

| オプション | 説明 |
|-----------|------|
| `--dry-run` | 実行計画のみ表示（実行しない） |
| `--sequential` | 並列実行せず順次実行 |
| `--continue-on-error` | エラーがあっても次のレイヤーを実行 |
| `--timeout <sec>` | 完了待機のタイムアウト（デフォルト: 3600） |
| `--interval <sec>` | 完了確認の間隔（デフォルト: 5） |
| `--workflow <name>` | 使用するワークフロー名 |
| `--base <branch>` | ベースブランチ |
| `-q, --quiet` | 進捗表示を抑制 |
| `-v, --verbose` | 詳細ログを出力 |

### 終了コード

| コード | 意味 |
|--------|------|
| 0 | 全Issue成功 |
| 1 | 一部Issueが失敗 |
| 2 | 循環依存を検出 |
| 3 | 引数エラー |

### 実行フロー

```
┌─────────────────────────────────────────────────────┐
│  1. 引数からIssue番号を取得                          │
├─────────────────────────────────────────────────────┤
│  2. 依存関係を解析（GitHub "Blocked by"）             │
├─────────────────────────────────────────────────────┤
│  3. 循環依存チェック                                 │
├─────────────────────────────────────────────────────┤
│  4. 実行レイヤーを計算                               │
│     - Layer 0: 依存なしのIssue                        │
│     - Layer 1: Layer 0に依存するIssue                 │
│     - Layer 2+: 同様に...                             │
├─────────────────────────────────────────────────────┤
│  5. レイヤーごとに実行                               │
│     - 同じレイヤー内は並列実行                        │
│     - 前のレイヤー完了後に次のレイヤー実行              │
├─────────────────────────────────────────────────────┤
│  6. 結果サマリーを表示                               │
└─────────────────────────────────────────────────────┘
```

### グローバルインストール時の使用

グローバルインストール後は `pi-batch` コマンドとして使用できます：

```bash
# グローバルインストール
./install.sh

# pi-batch コマンドで使用
pi-batch 42 43 44
```

## 並列実行の制御

### 同時実行数の制限

`.pi-runner.yaml` で設定:

```yaml
parallel:
  max_concurrent: 5  # 最大同時実行数（0 = 無制限）
```

**実装** (`lib/multiplexer.sh` / `lib/tmux.sh`):

```bash
# 並列実行数の制限をチェック
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
        log_error "Maximum concurrent sessions ($max_concurrent) reached."
        log_info "Currently running ($current_count sessions):"
        list_sessions | sed 's/^/  - /' >&2
        log_info "Use --force to override or cleanup existing sessions."
        return 1
    fi
    
    return 0
}
```

### 使用例

```bash
# 通常の並列起動（セッションにアタッチしない）
./scripts/run.sh 42 --no-attach
./scripts/run.sh 43 --no-attach
./scripts/run.sh 44 --no-attach

# 制限を超えた場合はエラー
./scripts/run.sh 45 --no-attach
# Error: Maximum concurrent sessions (3) reached.

# 強制的に起動
./scripts/run.sh 45 --force --no-attach
```

## セッション監視

### watch-session.sh

各タスクの完了を監視するバックグラウンドプロセス:

```bash
# scripts/run.sh から自動起動
nohup "$watcher_script" "$session_name" > "$watcher_log" 2>&1 &
```

**監視内容**:
1. Tmuxセッションの存在確認
2. 完了マーカー (`###TASK_COMPLETE_xxx###`) の検出
3. エラーマーカー (`###TASK_ERROR_xxx###`) の検出

**実装概要**:

```bash
# scripts/watch-session.sh の主要ロジック
monitor_session() {
    local session_name="$1"
    
    while true; do
        # セッションが終了したか確認
        if ! session_exists "$session_name"; then
            handle_session_ended "$session_name"
            break
        fi
        
        # セッション出力を確認
        local output
        output="$(get_session_output "$session_name" 100)"
        
        # 完了マーカーを検出
        if echo "$output" | grep -q "###TASK_COMPLETE_"; then
            handle_task_complete "$session_name"
            break
        fi
        
        # エラーマーカーを検出
        if echo "$output" | grep -q "###TASK_ERROR_"; then
            handle_task_error "$session_name" "$output"
            break
        fi
        
        sleep 5  # 5秒間隔でポーリング
    done
}
```

## 複数セッション待機

### wait-for-sessions.sh

複数のセッションが全て完了するまで待機:

```bash
# 使用例
./scripts/wait-for-sessions.sh 42 43 44

# 出力例
Waiting for 3 sessions to complete...
  - pi-issue-42: running
  - pi-issue-43: running
  - pi-issue-44: running

Session pi-issue-42 completed (success)
Session pi-issue-43 completed (success)  
Session pi-issue-44 completed (error)

Summary:
  Completed: 2
  Failed: 1
```

**実装概要**:

```bash
# scripts/wait-for-sessions.sh
wait_for_all_sessions() {
    local -a issue_numbers=("$@")
    local -A session_status
    
    # 初期状態を設定
    for issue in "${issue_numbers[@]}"; do
        local session_name
        session_name="$(generate_session_name "$issue")"
        session_status["$session_name"]="pending"
    done
    
    # 全セッション完了まで待機
    while true; do
        local all_done=true
        
        for session_name in "${!session_status[@]}"; do
            if [[ "${session_status[$session_name]}" == "pending" ]]; then
                if ! session_exists "$session_name"; then
                    # セッション終了を検出
                    local status
                    status="$(get_status "$(extract_issue_number "$session_name")")"
                    session_status["$session_name"]="$status"
                else
                    all_done=false
                fi
            fi
        done
        
        if [[ "$all_done" == "true" ]]; then
            break
        fi
        
        sleep 5
    done
    
    # 結果を出力
    print_summary "${!session_status[@]}"
}
```

## 状態管理

### ステータスファイル

各Issue用のステータスファイル:

**場所**: `.worktrees/.status/{issue_number}.json`

**形式**:
```json
{
  "issue": 42,
  "status": "running",
  "session": "pi-issue-42",
  "timestamp": "2024-01-30T09:00:00Z"
}
```

**状態一覧**:
- `running` - 実行中
- `complete` - 正常完了
- `error` - エラー終了

### 状態操作

```bash
# lib/status.sh を使用

# 状態を設定
set_status 42 "running"
set_status 42 "complete"
set_status 42 "error" "エラーメッセージ"

# 状態を取得
status="$(get_status 42)"

# エラーメッセージを取得
error_msg="$(get_error_message 42)"

# 全ステータスを一覧
list_all_statuses
# 出力: 42	running
#       43	complete
#       44	error
```

## エラーハンドリング

### 失敗時の動作

デフォルトでは、1つのタスクが失敗しても他のタスクは継続実行されます。

```bash
# 全タスクの結果を確認
./scripts/wait-for-sessions.sh 42 43 44
# → 失敗したタスクがあってもサマリーを表示

# 個別に確認
./scripts/status.sh 42
# Issue #42: error
# Error: テストが失敗しました
```

### リトライ

失敗したタスクを再実行:

```bash
# 既存セッション/worktreeを削除して再作成
./scripts/run.sh 42 --force
```

## リソース管理

### セッション一覧

```bash
# 実行中セッションを確認
./scripts/list.sh

# 出力例
Active sessions (2):
  pi-issue-42  .worktrees/issue-42-feature  running  5m
  pi-issue-43  .worktrees/issue-43-bugfix   running  3m
```

### クリーンアップ

```bash
# 特定のセッションをクリーンアップ
./scripts/cleanup.sh 42

# 全ての完了済みセッションをクリーンアップ
./scripts/cleanup.sh --all --completed

# 孤立したリソースをクリーンアップ
./scripts/cleanup.sh --orphaned
```

## パフォーマンス最適化

### 推奨設定

| 項目 | 推奨値 | 理由 |
|------|--------|------|
| `max_concurrent` | CPUコア数の50-75% | リソースの過負荷を防ぐ |
| ポーリング間隔 | 5秒 | バランスの取れた監視 |

### バッチ処理

大量のIssueを処理する場合:

```bash
#!/usr/bin/env bash
# batch-run.sh

issues=(42 43 44 45 46 47 48 49)
batch_size=3

for ((i=0; i<${#issues[@]}; i+=batch_size)); do
    batch=("${issues[@]:i:batch_size}")
    
    echo "Processing batch: ${batch[*]}"
    
    # バッチ内を並列起動
    for issue in "${batch[@]}"; do
        ./scripts/run.sh "$issue" --no-attach &
    done
    
    # バッチ完了を待機
    ./scripts/wait-for-sessions.sh "${batch[@]}"
    
    echo "Batch completed"
    sleep 2  # バッチ間で少し待機
done
```

## モニタリング

### リアルタイム状態確認

```bash
# 定期的に状態を表示
watch -n 5 './scripts/list.sh'

# 特定セッションの出力を確認
./scripts/attach.sh 42
# Ctrl+b d でデタッチ
```

### ログ確認

```bash
# 監視プロセスのログ
tail -f /tmp/pi-watcher-pi-issue-42.log

# Tmuxセッションの出力をキャプチャ
tmux capture-pane -t pi-issue-42 -p -S -100
```

## ベストプラクティス

1. **適切な並列数**
   - マシンスペックに応じて `max_concurrent` を設定
   - 推奨: CPUコア数の50-75%

2. **バックグラウンド実行**
   - `--no-attach` オプションで非対話的に起動
   - `wait-for-sessions.sh` で完了を待機

3. **エラー確認**
   - 各タスク完了後に `status.sh` で結果確認
   - エラー時は `--force` で再実行

4. **定期的なクリーンアップ**
   - 完了したセッションは速やかにクリーンアップ
   - `cleanup.sh --all --completed` で一括削除

5. **リソース監視**
   - ディスク容量を定期的にチェック
   - worktreeが増えすぎないよう管理
