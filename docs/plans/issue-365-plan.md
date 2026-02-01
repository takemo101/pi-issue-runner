# Issue #365 実装計画書

## 概要

`lib/cleanup-orphans.sh` と `lib/cleanup-plans.sh` のユニットテストを追加する。

## 影響範囲

- 新規ファイル:
  - `test/lib/cleanup-orphans.bats`
  - `test/lib/cleanup-plans.bats`

## 実装ステップ

### 1. cleanup-orphans.bats の作成

テスト対象: `cleanup_orphaned_statuses` 関数

#### テストケース:
1. 孤立したステータスファイルがない場合
2. 孤立したステータスファイルがある場合（削除実行）
3. dry-run モードで削除せずに表示のみ
4. age_days オプション指定時に古いファイルのみ対象

#### 依存関係:
- `lib/status.sh` の `find_orphaned_statuses`, `find_stale_statuses`, `remove_status`

### 2. cleanup-plans.bats の作成

テスト対象:
- `cleanup_old_plans` 関数
- `cleanup_closed_issue_plans` 関数

#### cleanup_old_plans テストケース:
1. 計画書がない場合
2. 保持件数以下の場合（削除なし）
3. 保持件数を超える場合（古いファイルを削除）
4. dry-run モード
5. keep_count=0 の場合（全て保持）

#### cleanup_closed_issue_plans テストケース:
1. 計画書がない場合
2. クローズされたIssueの計画書を削除
3. オープンなIssueの計画書は保持
4. dry-run モード
5. gh コマンドがない場合のエラー

## テスト方針

- 既存の `test/lib/status.bats` のパターンに従う
- `test_helper.bash` のセットアップ/ティアダウンを利用
- モック関数を使用してgh/gitコマンドをモック
- 一時ディレクトリでファイル操作をテスト

## リスクと対策

- **リスク**: macOS/Linux でファイルの日付変更方法が異なる
  - **対策**: `touch -t` コマンドを使用（POSIX互換）

- **リスク**: gh CLIのモックが必要
  - **対策**: `test_helper.bash` の `mock_gh` を拡張または再定義
