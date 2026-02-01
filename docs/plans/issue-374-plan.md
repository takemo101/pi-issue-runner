# Issue #374 実装計画書

## 概要

`lib/cleanup-orphans.sh` と `lib/cleanup-plans.sh` のユニットテストを追加し、テストカバレッジを向上させる。

## 影響範囲

### 新規作成ファイル
- `test/lib/cleanup-orphans.bats` - cleanup-orphans.sh のテスト
- `test/lib/cleanup-plans.bats` - cleanup-plans.sh のテスト

### 更新ファイル
- `AGENTS.md` - テストファイル一覧の更新

## 実装ステップ

### 1. cleanup-orphans.bats の作成

**対象関数**: `cleanup_orphaned_statuses(dry_run, age_days)`

**テストケース**:
1. dry_run=true で孤立ステータスの検出のみ（削除なし）
2. dry_run=false で孤立ステータスの実際の削除
3. 孤立ステータスがない場合の処理
4. age_days パラメータ指定時の動作
5. worktreeが存在するステータスは削除されないこと

### 2. cleanup-plans.bats の作成

**対象関数**:
- `cleanup_old_plans(dry_run, keep_count)`
- `cleanup_closed_issue_plans(dry_run)`

**テストケース for cleanup_old_plans**:
1. dry_run=true で計画書の検出のみ（削除なし）
2. dry_run=false で古い計画書の削除
3. keep_count=0 の場合は全て保持
4. 計画書が keep_count 以下の場合は削除なし
5. keep_count 件を超える計画書がある場合

**テストケース for cleanup_closed_issue_plans**:
1. dry_run=true でクローズ済みIssueの計画書検出のみ
2. dry_run=false でクローズ済みIssueの計画書削除
3. オープン中のIssueの計画書は削除されない
4. gh コマンドが使用できない場合のエラーハンドリング

### 3. AGENTS.md の更新

test/lib/ セクションに新規テストファイルを追記:
- `cleanup-orphans.bats`
- `cleanup-plans.bats`

## テスト方針

- 既存の `test_helper.bash` を活用
- モック関数を使用してGitHub CLIの呼び出しをモック化
- 一時ディレクトリを使用してファイルシステム操作をテスト
- dry_run モードのテストを優先（副作用なし）

## リスクと対策

| リスク | 対策 |
|--------|------|
| gh コマンドのモックが複雑 | 既存のmock_gh関数を拡張 |
| macOS/Linux のfind差異 | 両環境でテスト、または条件分岐 |
| 日付操作のテスト | touch -t を使用して日付を制御 |

## 受け入れ条件チェックリスト

- [ ] `test/lib/cleanup-orphans.bats` が作成されている
- [ ] `test/lib/cleanup-plans.bats` が作成されている
- [ ] 各関数の正常系テストが実装されている
- [ ] 各関数の異常系テストが実装されている
- [ ] AGENTS.md が更新されている
- [ ] `./scripts/test.sh lib` で全テストがパスする
