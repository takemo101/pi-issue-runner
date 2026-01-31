# 実装計画書: Issue #204 - 旧形式テストのBats形式への完全移行

## 概要

旧形式テスト（`*_test.sh`）をBats形式（`.bats`）に変換し、テスト実行方法を統一します。

## 現状分析

### 既存のBatsテスト（6ファイル）
```
test/lib/config.bats       ✅ Bats形式
test/lib/github.bats       ✅ Bats形式
test/lib/log.bats          ✅ Bats形式
test/scripts/cleanup.bats  ✅ Bats形式
test/scripts/list.bats     ✅ Bats形式
test/scripts/run.bats      ✅ Bats形式
```

### 旧形式テスト（16ファイル）
| ファイル | 重複状態 | 対応方針 |
|---------|---------|---------|
| config_test.sh | ✅ Batsと重複 | 削除（Batsにマージ済み） |
| log_test.sh | ✅ Batsと重複 | マージ後削除 |
| github_test.sh | ✅ Batsと重複 | マージ後削除 |
| cleanup_test.sh | ✅ Batsと重複 | 削除（Batsにマージ済み） |
| list_test.sh | ✅ Batsと重複 | 削除（Batsにマージ済み） |
| run_test.sh | ✅ Batsと重複 | マージ後削除 |
| attach_test.sh | ⚠️ 新規変換必要 | → test/scripts/attach.bats |
| improve_test.sh | ⚠️ 新規変換必要 | → test/scripts/improve.bats |
| init_test.sh | ⚠️ 新規変換必要 | → test/scripts/init.bats |
| notify_test.sh | ⚠️ 新規変換必要 | → test/lib/notify.bats |
| status_test.sh | ⚠️ 新規変換必要 | → test/lib/status.bats |
| stop_test.sh | ⚠️ 新規変換必要 | → test/scripts/stop.bats |
| tmux_test.sh | ⚠️ 新規変換必要 | → test/lib/tmux.bats |
| workflow_test.sh | ⚠️ 新規変換必要 | → test/lib/workflow.bats |
| worktree_test.sh | ⚠️ 新規変換必要 | → test/lib/worktree.bats |
| wait_for_sessions_test.sh | ⚠️ 新規変換必要 | → test/scripts/wait-for-sessions.bats |
| watch_session_test.sh | ⚠️ 新規変換必要 | → test/scripts/watch-session.bats |
| critical_fixes_test.sh | ⚠️ 新規変換必要 | → test/regression/critical-fixes.bats |

## 影響範囲

### 変更対象ファイル
- `test/*.sh` - 16ファイル削除
- `test/lib/*.bats` - 6ファイル追加（notify, status, tmux, workflow, worktree）+ log.bats更新
- `test/scripts/*.bats` - 7ファイル追加（attach, improve, init, stop, wait-for-sessions, watch-session）+ run.bats更新
- `test/regression/critical-fixes.bats` - 1ファイル追加
- `AGENTS.md` - 旧形式テストの記述を削除

### 影響なし
- `test/test_helper.bash` - 既存のまま
- `test/helpers/mocks.sh` - 既存のまま
- `scripts/test.sh` - 既に Bats 対応済み

## 実装ステップ

### Step 1: 既存Batsテストへのマージ（重複分）

1. **log_test.sh → test/lib/log.bats**
   - `set_log_level` テスト追加
   - `enable_verbose`/`enable_quiet` テスト追加
   - 関数存在テスト追加

2. **github_test.sh → test/lib/github.bats**
   - `get_issues_created_after` テスト追加
   - ghモック関数テスト追加

3. **run_test.sh → test/scripts/run.bats**
   - スクリプト構造テスト追加

### Step 2: lib/ ディレクトリのBatsテスト作成

1. **test/lib/notify.bats** ← notify_test.sh
2. **test/lib/status.bats** ← status_test.sh
3. **test/lib/tmux.bats** ← tmux_test.sh
4. **test/lib/workflow.bats** ← workflow_test.sh
5. **test/lib/worktree.bats** ← worktree_test.sh

### Step 3: scripts/ ディレクトリのBatsテスト作成

1. **test/scripts/attach.bats** ← attach_test.sh
2. **test/scripts/improve.bats** ← improve_test.sh
3. **test/scripts/init.bats** ← init_test.sh
4. **test/scripts/stop.bats** ← stop_test.sh
5. **test/scripts/wait-for-sessions.bats** ← wait_for_sessions_test.sh
6. **test/scripts/watch-session.bats** ← watch_session_test.sh

### Step 4: regression ディレクトリ作成

1. **test/regression/critical-fixes.bats** ← critical_fixes_test.sh

### Step 5: 旧形式テストの削除

すべての `*_test.sh` ファイルを削除

### Step 6: ドキュメント更新

`AGENTS.md` から旧形式テストの参照を削除

## テスト方針

### 変換パターン

旧形式:
```bash
assert_equals "description" "expected" "$actual"
```

Bats形式:
```bash
@test "description" {
    result="$actual"
    [ "$result" = "expected" ]
}
```

### モックの活用

- `test_helper.bash` の既存モック関数を使用
- `helpers/mocks.sh` の関数ベースモックを必要に応じて活用

## リスクと対策

| リスク | 対策 |
|-------|------|
| テストケースの漏れ | 旧形式テストのテストケースを全てカウントし、Bats形式でも同数以上確保 |
| 環境依存テストの失敗 | skip を活用して環境依存テストをスキップ可能に |
| モック不足 | 必要に応じて test_helper.bash にモック追加 |

## 完了条件

- [ ] `test/*.sh` から `*_test.sh` ファイルがなくなっている
- [ ] 全テストが `bats test/**/*.bats` で実行できる
- [ ] `./scripts/test.sh` が正常に動作する
- [ ] AGENTS.md から「旧形式テスト実行」の記述が削除されている
