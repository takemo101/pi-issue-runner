# Issue #221 実装計画

## 概要

旧形式テストファイル（`test/*.sh`）を削除し、Batsテストに完全移行する。

## 現状分析

### テストファイルの内訳

| カテゴリ | ファイル数 | 場所 |
|----------|-----------|------|
| Bats (lib) | 8 | `test/lib/*.bats` |
| Bats (scripts) | 10 | `test/scripts/*.bats` |
| 旧形式 | 18 | `test/*.sh` |

### カバレッジ対応表

すべての旧形式テストはBatsテストでカバー済み：

| 旧形式テスト | 対応Batsテスト |
|-------------|---------------|
| attach_test.sh | test/scripts/attach.bats |
| cleanup_test.sh | test/scripts/cleanup.bats |
| config_test.sh | test/lib/config.bats |
| critical_fixes_test.sh | 複数のBatsテストでカバー済み |
| github_test.sh | test/lib/github.bats |
| improve_test.sh | test/scripts/improve.bats |
| init_test.sh | test/scripts/init.bats |
| list_test.sh | test/scripts/list.bats |
| log_test.sh | test/lib/log.bats |
| notify_test.sh | test/lib/notify.bats |
| run_test.sh | test/scripts/run.bats |
| status_test.sh | test/lib/status.bats + test/scripts/status.bats |
| stop_test.sh | test/scripts/stop.bats |
| tmux_test.sh | test/lib/tmux.bats |
| wait_for_sessions_test.sh | test/scripts/wait-for-sessions.bats |
| watch_session_test.sh | test/scripts/watch-session.bats |
| workflow_test.sh | test/lib/workflow.bats |
| worktree_test.sh | test/lib/worktree.bats |

## 影響範囲

### 削除対象

1. **旧形式テストファイル** (18ファイル): `test/*_test.sh`
2. **レガシーモック**: `test/helpers/mocks.sh`
3. **空のhelpersディレクトリ**: `test/helpers/`

### 更新対象

1. **AGENTS.md**: 旧形式テストの記述を削除

### 保持対象

- `test/test_helper.bash`: Batsテストで使用中
- `test/fixtures/`: 将来の拡張用に保持
- `test/lib/*.bats`, `test/scripts/*.bats`: 現行テスト

## 実装ステップ

1. 旧形式テストファイルの削除 (`test/*_test.sh`)
2. `test/helpers/` ディレクトリの削除
3. `AGENTS.md` の更新
   - 「旧形式テスト実行」の記述を削除
   - ディレクトリ構造から `helpers/` を削除
4. テスト実行で全てパスすることを確認

## テスト方針

- `./scripts/test.sh` で全Batsテストがパスすることを確認

## リスクと対策

| リスク | 対策 |
|-------|------|
| 削除したテストに固有のテストケースがあった | 事前に各テストを確認済み。critical_fixes_test.shの内容もBatsテストでカバー済み |
| ドキュメント不整合 | AGENTS.mdを同時に更新 |
