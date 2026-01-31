# Issue #289 実装計画書

## 概要

`agents/merge.md` の計画書削除処理が worktree 環境から実行されるため、ホスト環境に反映されない問題を修正する。

## 問題分析

### 根本原因
1. `merge.md` のステップ4で計画書削除を実行
2. `gh pr merge --merge --delete-branch` 実行後、ブランチが削除される
3. worktree は削除されたブランチを参照しているため、main への push が失敗
4. そもそも worktree 内での変更はホストの `docs/plans/` に反映されない

### 現在のフロー
```
merge.md (worktree内)
  → PR マージ
  → ブランチ削除
  → 計画書削除 (worktree内で実行 → ホストに反映されない)
  → TASK_COMPLETE マーカー出力

watch-session.sh (ホスト)
  → マーカー検出
  → cleanup.sh 実行 (worktree削除のみ)
```

## 影響範囲

- `agents/merge.md` - 計画書削除ステップの削除
- `scripts/watch-session.sh` - cleanup 時に計画書も削除するよう修正
- `test/scripts/watch-session.bats` - テスト追加

## 実装ステップ

### 1. `agents/merge.md` の修正
- ステップ4「計画書の削除」を削除
- 計画書削除はホスト環境（`watch-session.sh`）で行うことを明記

### 2. `scripts/watch-session.sh` の修正
- 完了マーカー検出後、cleanup 前に計画書を削除
- ホスト環境で直接ファイルを削除するため、worktree の問題は発生しない

### 3. テスト追加
- `watch-session.sh` が計画書を削除することを確認するテスト

### 4. 既存の残存計画書のクリーンアップ
- `cleanup.sh --delete-plans` を実行して既存の残存計画書を削除（手動実行）

## テスト方針

1. **ユニットテスト**: `test/scripts/watch-session.bats` に計画書削除のテストを追加
2. **回帰テスト**: 既存のテストが引き続きパスすることを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| ホスト環境でファイル削除に失敗 | 削除失敗時もエラーとせず、警告のみ出力（既存動作に影響なし） |
| 進行中のIssueの計画書を誤って削除 | Issue番号で特定するため、誤削除のリスクは低い |

## 受け入れ条件

- [x] マージ完了後、計画書が自動的に削除される（ホスト環境で）
- [ ] 既存の残存計画書がクリーンアップされる（手動実行）
- [x] 回帰テストを追加
