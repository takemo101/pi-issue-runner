# Implementation Plan: Issue #355

## 概要

`lib/cleanup-orphans.sh` と `lib/cleanup-plans.sh` に対応するBatsテストファイルを作成する。

## 影響範囲

### 新規作成ファイル
- `test/lib/cleanup-orphans.bats`
- `test/lib/cleanup-plans.bats`

### 関連ファイル
- `lib/cleanup-orphans.sh` - テスト対象
- `lib/cleanup-plans.sh` - テスト対象
- `lib/status.sh` - cleanup-orphans.shの依存
- `lib/config.sh` - cleanup-plans.shの依存
- `test/test_helper.bash` - テストヘルパー

## 実装ステップ

### Step 1: test/lib/cleanup-orphans.bats の作成

テスト対象関数: `cleanup_orphaned_statuses()`

テストケース:
1. dry_run=true の場合、ログ出力のみで削除しない
2. dry_run=false の場合、孤立ステータスを実際に削除
3. age_days指定時、古いファイルのみ対象
4. 孤立ファイルがない場合の正常動作
5. ログ出力の検証

### Step 2: test/lib/cleanup-plans.bats の作成

テスト対象関数:
- `cleanup_old_plans()`
- `cleanup_closed_issue_plans()`

テストケース（cleanup_old_plans）:
1. keep_count に基づくローテーション
2. dry_run=true でログ出力のみ
3. dry_run=false で実際に削除
4. keep_count=0 で全て保持
5. 計画書がない場合の正常動作

テストケース（cleanup_closed_issue_plans）:
1. クローズ済みIssueの計画書削除
2. dry_run モードのテスト
3. オープン中Issueの計画書は保持
4. ghコマンドのモック使用

## テスト方針

- 既存の `test/lib/status.bats` のパターンを踏襲
- `test_helper.bash` のセットアップ/ティアダウンを使用
- 一時ディレクトリでテスト実行
- ghコマンドはモックで対応

## リスクと対策

### リスク1: ファイルシステム操作の競合
- 対策: 各テストで独立した一時ディレクトリを使用

### リスク2: macOS/Linux間の互換性
- 対策: stat コマンドの差異を考慮（cleanup-plans.sh で既に対応済み）

### リスク3: ghコマンドの依存
- 対策: モックを使用してテスト

## 完了条件

- [x] test/lib/cleanup-orphans.bats 作成
- [x] test/lib/cleanup-plans.bats 作成
- [x] 全テストがパスする
- [x] ShellCheckが通る
