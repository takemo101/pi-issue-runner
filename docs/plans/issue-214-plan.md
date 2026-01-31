# 実装計画: Issue #214 - cleanup.sh should remove orphaned status files

## 概要

worktree削除時に対応するステータスファイル（`.worktrees/.status/<issue>.json`）が残存する問題を修正し、孤立したステータスファイルをクリーンアップする機能を追加する。

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `scripts/cleanup.sh` | worktree削除時にステータスファイル削除を追加、`--orphans`オプション追加 |
| `lib/status.sh` | 孤立ステータスファイル検出関数を追加 |
| `test/scripts/cleanup.bats` | 新機能のテスト追加 |
| `test/lib/status.bats` | 孤立検出関数のテスト追加 |

## 実装ステップ

### Step 1: lib/status.sh に孤立ステータス検出関数を追加

`find_orphaned_statuses()` 関数を追加:
- `.worktrees/.status/` 内の全JSONファイルをスキャン
- 対応するworktree（`issue-<番号>-*`）が存在するか確認
- 存在しないものをリストアップ

```bash
# 孤立したステータスファイルを検出
# 出力: 孤立したIssue番号（1行に1つ）
find_orphaned_statuses() {
    # 実装...
}
```

### Step 2: scripts/cleanup.sh でworktree削除時にステータスファイルも削除

worktree削除処理に `remove_status` 呼び出しを追加:

```bash
# Worktree削除後にステータスファイルも削除
if [[ "$keep_worktree" == "false" ]]; then
    # ... worktree削除処理 ...
    remove_status "$issue_number"  # 追加
fi
```

### Step 3: scripts/cleanup.sh に `--orphans` オプションを追加

新しいオプション:
- `--orphans`: 孤立したステータスファイルのみをクリーンアップ
- `--dry-run`: 削除せずに対象を表示（`--orphans`と組み合わせて使用）

使用例:
```bash
./scripts/cleanup.sh --orphans           # 孤立ファイルを削除
./scripts/cleanup.sh --orphans --dry-run # 対象のみ表示
```

### Step 4: テストの追加

**test/lib/status.bats:**
- `find_orphaned_statuses` 関数のテスト

**test/scripts/cleanup.bats:**
- `--orphans`オプションのテスト
- worktree削除時のステータスファイル削除テスト

## テスト方針

1. **ユニットテスト**: 
   - `find_orphaned_statuses()` が正しく孤立ファイルを検出するか
   - 正常なファイルは検出されないか

2. **統合テスト**:
   - `cleanup.sh --orphans` が孤立ファイルを削除するか
   - `cleanup.sh <issue>` がステータスファイルも削除するか
   - `--dry-run` が実際に削除しないか

3. **手動テスト**:
   - 現在の孤立ファイルを確認
   - `--orphans --dry-run` で対象を確認
   - `--orphans` で削除を実行

## リスクと対策

| リスク | 対策 |
|--------|------|
| 誤って有効なステータスファイルを削除 | worktree存在チェックを慎重に実装 |
| 既存のcleanup動作への影響 | 既存テストの継続パスを確認 |
| パフォーマンス（大量ファイル時） | ステータスファイル数は通常少数なので問題なし |

## 受け入れ条件チェックリスト

- [ ] worktree削除時に対応するステータスファイルも削除される
- [ ] `--orphans` オプションで孤立ステータスファイルをクリーンアップできる
- [ ] `--dry-run` オプションで削除対象を事前確認できる
- [ ] 全テストがパスする
