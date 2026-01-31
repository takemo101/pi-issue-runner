# 実装計画: Issue #247

## fix: improve.sh中断時にworktreeがクリーンアップされない

### 概要

improve.shが中断された場合（Ctrl+C、エラー等）、実行中のセッションのworktreeがクリーンアップされずに残る問題を修正する。

### 原因分析

1. **クリーンアップのタイミング**: watch-session.shが完了マーカーを検出した時のみcleanup.shを実行
2. **中断時の挙動**: improve.shが中断されると、wait-for-sessions.shも終了し、watch-session.shの監視が中断される
3. **結果**: 完了マーカーが検出されないため、worktreeとセッションが残る

### 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `scripts/improve.sh` | EXITトラップを追加してクリーンアップ処理を実装 |
| `scripts/wait-for-sessions.sh` | 完了時にcleanup.shを呼び出す |
| `test/scripts/improve.bats` | 新規：improve.shのテスト |
| `test/scripts/wait-for-sessions.bats` | 既存テストの更新 |

### 実装ステップ

#### 1. improve.shにトラップを追加

```bash
# 実行中のセッションを追跡
declare -a ACTIVE_SESSIONS=()

cleanup_on_exit() {
    log_warn "Cleaning up on exit..."
    for issue in "${ACTIVE_SESSIONS[@]}"; do
        "$SCRIPT_DIR/cleanup.sh" "pi-issue-$issue" --force 2>/dev/null || true
    done
}

trap cleanup_on_exit EXIT INT TERM
```

- run.shでセッション開始後、Issue番号をACTIVE_SESSIONSに追加
- wait-for-sessions.sh完了後、ACTIVE_SESSIONSをクリア

#### 2. wait-for-sessions.shにクリーンアップオプションを追加

```bash
# --cleanup オプション追加
# 完了検出時にcleanup.shを実行
complete)
    completed_list="$completed_list $issue"
    if [[ "$cleanup" == "true" ]]; then
        "$SCRIPT_DIR/cleanup.sh" "pi-issue-$issue" --force 2>/dev/null || true
    fi
    ;;
```

#### 3. improve.shからwait-for-sessions.shを--cleanupオプション付きで呼び出し

### テスト方針

1. **ユニットテスト**
   - improve.shのトラップ関数のテスト
   - wait-for-sessions.shの--cleanupオプションのテスト

2. **統合テスト**
   - 正常完了時のクリーンアップ確認
   - タイムアウト時のクリーンアップ確認

3. **手動テスト**
   - Ctrl+Cでの中断時にworktreeが削除されることを確認

### リスクと対策

| リスク | 対策 |
|-------|------|
| クリーンアップ中にエラーが発生 | `|| true`で握り潰し、ログ出力で追跡可能に |
| 未コミットの変更がある場合 | `--force`オプションを使用 |
| セッションが既に削除されている | cleanup.shはエラーを無視する設計 |

### 完了条件

- [x] Issueの要件を完全に理解した
- [x] 関連するコードを調査した
- [x] 実装計画書を作成した
- [x] 計画書をファイルに保存した
