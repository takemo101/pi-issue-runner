# 実装計画: Issue #238

## 概要

`wait-for-sessions.sh` がクリーンアップ済みセッションで永久待機する問題を修正する。

## 問題点

現在の `unknown` ステータスの処理：
```bash
unknown)
    # セッションがまだ開始されていないか、既にクリーンアップ済み
    all_done=false  # ← 常に待機してしまう
    ;;
```

`unknown` ステータスには2つのケースがある：
1. **セッションがまだ開始されていない** → 待機すべき
2. **セッションが完了してクリーンアップ済み** → 完了として扱うべき

## 影響範囲

- `scripts/wait-for-sessions.sh` - メイン修正対象
- `test/scripts/wait-for-sessions.bats` - テスト追加

## 実装ステップ

### 1. wait-for-sessions.shの修正

`unknown` ケースで tmux セッションの存在をチェックして判断する：

```bash
unknown)
    # tmuxセッションが存在するか確認
    local session_name="pi-issue-$issue"
    if tmux has-session -t "$session_name" 2>/dev/null; then
        # セッションはあるがステータス不明 → まだ開始中
        all_done=false
    else
        # セッションがない → 完了済みとして扱う
        completed_list="$completed_list $issue"
        if [[ "$quiet" != "true" ]]; then
            echo "[✓] Issue #$issue 完了（セッション終了済み）"
        fi
    fi
    ;;
```

### 2. テストの追加

以下のケースをテスト：
1. unknownステータス + tmuxセッションなし → 完了として扱う
2. unknownステータス + tmuxセッションあり → 待機を続ける（タイムアウトでテスト）

## テスト方針

- 単体テスト: Batsテストで tmux コマンドをモックして検証
- 回帰テスト: 既存テストが引き続きパスすることを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| tmux コマンドが失敗するケース | `2>/dev/null` でエラーを抑制済み |
| 競合状態（セッション終了直後） | セッションなし=完了として扱う |

## 見積もり

- 実装: 15分
- テスト: 15分
- **合計: 30分**
