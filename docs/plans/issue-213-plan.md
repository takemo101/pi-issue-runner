# Issue #213 Implementation Plan

## 概要

旧形式のシェルスクリプトテスト（`*_test.sh`）を削除し、Batsテストに統一する。

## 影響範囲

### 削除対象ファイル
- `test/attach_test.sh`
- `test/cleanup_test.sh`
- `test/config_test.sh`
- `test/critical_fixes_test.sh`
- `test/github_test.sh`
- `test/improve_test.sh`
- `test/init_test.sh`
- `test/list_test.sh`
- `test/log_test.sh`
- `test/notify_test.sh`
- `test/run_test.sh`
- `test/status_test.sh`
- `test/stop_test.sh`
- `test/tmux_test.sh`
- `test/wait_for_sessions_test.sh`
- `test/watch_session_test.sh`
- `test/workflow_test.sh`
- `test/worktree_test.sh`

### 修正対象ファイル
- `scripts/test.sh`: `--legacy` オプションを削除
- `AGENTS.md`: 旧形式テストの記載を削除

### 既存Batsテストの問題修正
1. `test/lib/github.bats`: `detect_dangerous_patterns`関数が存在しないためテストを削除
2. `test/scripts/improve.bats`: 存在しないオプション(`--auto-continue`, `--dry-run`, `--review-only`)のテストを削除

## 実装ステップ

1. **Batsテストの問題修正**
   - `test/lib/github.bats`から存在しない関数のテストを削除
   - `test/scripts/improve.bats`から存在しないオプションのテストを削除

2. **カバレッジ確認**
   - Batsテストと旧形式テストの比較
   - 旧形式にあってBatsにないテストケースの確認（なし）

3. **旧形式テストファイルの削除**
   - 18個の `*_test.sh` ファイルを削除

4. **scripts/test.sh の更新**
   - `--legacy` オプションを削除
   - `run_legacy_tests` 関数を削除

5. **ドキュメント更新**
   - `AGENTS.md` から旧形式テストの記載を削除

## テスト方針

- 修正後にBatsテストを実行して全テストがパスすることを確認
- `./scripts/test.sh` が正常に動作することを確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 旧形式にしかないテストケースがある | 事前にテストケースを比較し、必要に応じてBatsに移行（調査済み：移行不要） |
| --legacyオプションを使用しているユーザー | 破壊的変更としてドキュメントに記載 |

## 調査結果

### テストカバレッジの比較

| 機能 | Batsテスト | 旧形式テスト | 備考 |
|------|-----------|-------------|------|
| config.sh | ✅ 11 tests | 簡易テスト | Batsで完全カバー |
| github.sh | ✅ 16 tests | 簡易テスト | Batsで完全カバー |
| log.sh | ✅ 9 tests | 簡易テスト | Batsで完全カバー |
| notify.sh | ✅ 13 tests | 簡易テスト | Batsで完全カバー |
| status.sh | ✅ 22 tests | 簡易テスト | Batsで完全カバー |
| tmux.sh | ✅ 18 tests | 簡易テスト | Batsで完全カバー |
| workflow.sh | ✅ 29 tests | 簡易テスト | Batsで完全カバー |
| worktree.sh | ✅ 16 tests | 簡易テスト | Batsで完全カバー |
| scripts/*.sh | ✅ 109 tests | 簡易テスト | Batsで完全カバー |

旧形式テストにユニークなテストケースはなく、すべてBatsテストでカバーされている。

## 完了条件

- [x] Issueの要件を完全に理解した
- [x] 関連するコードを調査した
- [x] 実装計画書を作成した
- [x] 計画書をファイルに保存した
