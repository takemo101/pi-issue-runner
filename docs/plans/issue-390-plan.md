# Implementation Plan: Issue #390

## 概要
セッション完了後のクリーンアップが不完全になる問題を修正します。具体的には、worktreeとブランチが残存する問題に対処し、 orphaned worktree の検出・修復機能も実装します。

## 影響範囲

### 変更対象ファイル
1. `lib/worktree.sh` - worktree削除のリトライ処理とエラーログ追加
2. `scripts/cleanup.sh` - 強制削除オプションの使用とエラーハンドリング改善
3. `scripts/watch-session.sh` - クリーンアップ失敗時の再試行と orphaned worktree 検出
4. `lib/cleanup-orphans.sh` - 新規: complete状態だがworktreeが残存しているケースの検出

### 依存関係
- `lib/status.sh` - ステータス管理（変更なし、既存機能使用）
- `lib/log.sh` - ログ出力（変更なし）

## 実装ステップ

### Step 1: worktree.sh の強化
- `remove_worktree()` にリトライ処理を追加（最大3回）
- 削除失敗時の詳細なエラーログを出力
- `git worktree remove --force` の使用を改善

### Step 2: cleanup.sh の強化
- worktree削除のエラーハンドリングを改善
- ブランチ削除のエラーハンドリングを改善
- 各ステップの成否をログに記録
- hook失敗時も後続処理を継続

### Step 3: cleanup-orphans.sh の拡張
- 新規関数 `find_complete_but_existing_worktrees()` を追加
- complete状態だがworktreeが残存しているケースを検出
- 自動修復または警告出力機能

### Step 4: watch-session.sh の強化
- クリーンアップ失敗時の再試行処理（最大2回）
- orphaned worktree検出と修復を完了後に実行

### Step 5: テスト追加
- `test/lib/worktree.bats` - リトライ処理のテスト
- `test/scripts/cleanup.bats` - エラーハンドリングのテスト
- `test/lib/cleanup-orphans.bats` - orphaned worktree検出のテスト

## テスト方針

### 単体テスト
1. worktree削除のリトライ処理（成功/失敗ケース）
2. cleanup.sh のエラーハンドリング
3. orphaned worktree検出機能

### 統合テスト
1. セッション完了時のクリーンアップフロー全体
2. クリーンアップ失敗時の再試行

### 手動テスト
1. 実際にセッションを完了させてクリーンアップを確認
2. orphaned worktreeの検出・修復確認

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| リトライ処理で無限ループ | 高 | 最大3回までの試行制限 |
| force削除でデータ損失 | 中 | --forceオプションは明示的に指定された場合のみ使用 |
| 誤った orphaned worktree検出 | 中 | 状態ファイルの内容を確認して確実にcomplete状態のもののみ対象 |
| 既存機能の破壊 | 高 | 既存のテストを全てパスさせる |

## 受け入れ条件

- [x] クリーンアップ失敗の根本原因を特定（watch-session.shのエラーハンドリング）
- [x] worktree削除のリトライ処理を実装
- [x] orphaned worktree検出・修復機能を実装
- [x] クリーンアップ失敗時にエラーログを出力
- [x] 既存のorphaned worktreeを一括削除するオプションを追加
- [x] 全てのテストがパスすること

## 関連Issue
- #390 - セッション完了後のクリーンアップが不完全になる問題
