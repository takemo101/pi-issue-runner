# GitHub Issue #568 実装計画

## 概要

`lib/tmux.sh` の `kill_session` 関数に、セッション終了後の待機処理を追加します。これにより、worktreeクリーンアップ時に発生する `ENOENT: no such file or directory, uv_cwd` エラーを防止します。

## 背景

自動クリーンアップ時に以下のエラーが発生することがありました：

```
mise WARN  Current directory does not exist or is not accessible: .../.worktrees/issue-XXX
Error: ENOENT: no such file or directory, uv_cwd
```

### 原因

`cleanup.sh` の処理順序：
1. `kill_session` でtmuxセッションに終了シグナルを送信
2. **即座に** `remove_worktree` でディレクトリを削除

しかし、`kill_session` は `tmux kill-session` を実行するだけで、セッションが**完全に終了するまで待機しない**。

結果として：
- tmuxセッション内のpiプロセスがまだ終了処理中
- worktreeディレクトリが削除される
- piが出力しようとすると `ENOENT` エラー

## 実装内容

### 変更対象ファイル

- `lib/tmux.sh` - `kill_session` 関数の改善（実装済み）

### 実装詳細

`kill_session` 関数に以下の機能を追加：

1. **最大待機秒数のパラメータ化**: `max_wait` パラメータ（デフォルト10秒）
2. **セッション終了待機ループ**: `session_exists` がfalseを返すまで待機
3. **タイムアウト処理**: 最大待機時間を超えた場合は警告を出力
4. **成功/失敗のログ出力**: デバッグログで終了状態を記録

```bash
kill_session() {
    local session_name="$1"
    local max_wait="${2:-10}"  # 最大待機秒数（デフォルト10秒）
    
    # ... 既存のチェック ...
    
    tmux kill-session -t "$session_name"
    
    # セッションが完全に終了するまで待機
    local waited=0
    while session_exists "$session_name" && [[ "$waited" -lt "$max_wait" ]]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    
    if session_exists "$session_name"; then
        log_warn "Session $session_name still exists after ${max_wait}s wait"
        return 1
    fi
    
    log_debug "Session $session_name terminated successfully"
    return 0
}
```

## テスト方針

### 単体テスト（Bats）

`test/lib/tmux.bats` に以下のテストケースを追加：

1. **既存しないセッションの終了**: 存在しないセッション名を指定した場合、警告を出して成功を返す
2. **カスタム待機時間**: `max_wait` パラメータが正しく機能する
3. **セッション終了待機**: 実際のセッションが終了するまで待機することを確認

### 手動テスト

1. Issueを実行してタスクを完了させる
2. 自動クリーンアップが実行される
3. `ENOENT` エラーが発生しないことを確認

## 影響範囲

- `lib/tmux.sh` の `kill_session` 関数のみ
- 既存の呼び出し元に変更は不要（デフォルト引数を使用）
- 後方互換性あり

## リスクと対策

| リスク | 対策 |
|--------|------|
| 待機時間が長すぎる | デフォルト10秒、カスタマイズ可能 |
| セッションが終了しない | タイムアウト後に警告を出力して続行 |
| 既存コードへの影響 | デフォルト引数で既存の呼び出しと互換 |

## 完了条件

- [x] `kill_session` 関数に待機処理を追加
- [ ] テストケースを追加
- [ ] 全てのテストがパス
- [ ] ドキュメントを更新（必要に応じて）
