# Issue #200 実装計画書

## 概要

Batsテストが存在しないライブラリファイル（`notify.sh`, `status.sh`, `tmux.sh`, `workflow.sh`, `worktree.sh`）に対して、Batsテストファイルを作成する。

## 影響範囲

### 新規作成ファイル
- `test/lib/notify.bats`
- `test/lib/status.bats`
- `test/lib/tmux.bats`
- `test/lib/workflow.bats`
- `test/lib/worktree.bats`

### 参照するライブラリ
- `lib/notify.sh` - 通知機能（macOS/Linux対応）
- `lib/status.sh` - ステータスファイル管理
- `lib/tmux.sh` - tmux操作
- `lib/workflow.sh` - ワークフローエンジン
- `lib/worktree.sh` - Git worktree操作

## 実装ステップ

### 1. test/lib/status.bats
`status.sh`は基本的なJSON操作とステータス管理を行う。テスト内容：
- `json_escape()` - JSON文字列エスケープ
- `get_status_dir()` - ステータスディレクトリパス取得
- `save_status()` / `load_status()` - ステータス保存・読み込み
- `set_status()` / `get_status()` - エイリアス関数
- `list_all_statuses()` - 全ステータス一覧

### 2. test/lib/notify.bats
`notify.sh`はプラットフォーム検出と通知機能を提供。テスト内容：
- `is_macos()` / `is_linux()` - プラットフォーム検出
- `notify_error()` / `notify_success()` - 通知関数（モック使用）
- `handle_error()` / `handle_complete()` - 統合処理

### 3. test/lib/tmux.bats
`tmux.sh`はtmuxセッション管理を行う。テスト内容：
- `generate_session_name()` - セッション名生成
- `extract_issue_number()` - セッション名からIssue番号抽出
- `session_exists()` - セッション存在確認（モック使用）
- `list_sessions()` - セッション一覧（モック使用）

### 4. test/lib/workflow.bats
`workflow.sh`はワークフロー定義の読み込みと実行を行う。テスト内容：
- `find_workflow_file()` - ワークフローファイル検索
- `get_workflow_steps()` - ステップ一覧取得
- `render_template()` - テンプレート変数展開
- `generate_workflow_prompt()` - プロンプト生成

### 5. test/lib/worktree.bats
`worktree.sh`はGit worktree操作を行う。テスト内容：
- `create_worktree()` - worktree作成（モック使用）
- `remove_worktree()` - worktree削除（モック使用）
- `list_worktrees()` - worktree一覧
- `find_worktree_by_issue()` - Issue番号からworktree検索

## テスト方針

1. 各テストファイルに最低3つのテストケースを含める（受け入れ条件）
2. 外部コマンド（git, tmux, osascript等）はモックを使用
3. 既存の `test_helper.bash` のモック関数を活用
4. テスト用一時ディレクトリ（`BATS_TEST_TMPDIR`）を使用
5. 既存の `*_test.sh` のテストケースを参考にBats形式に移行

## リスクと対策

| リスク | 対策 |
|--------|------|
| モックが複雑になる | 既存のtest_helper.bashのモック関数を拡張 |
| プラットフォーム依存テスト | 条件分岐でスキップ処理を追加 |
| config.shの事前読み込み | setup()でconfig.shを明示的に初期化 |

## 受け入れ条件チェックリスト

- [ ] `test/lib/notify.bats` が作成されている
- [ ] `test/lib/status.bats` が作成されている
- [ ] `test/lib/tmux.bats` が作成されている
- [ ] `test/lib/workflow.bats` が作成されている
- [ ] `test/lib/worktree.bats` が作成されている
- [ ] `bats test/lib/*.bats` が正常に実行できる
- [ ] 各テストファイルに最低3つのテストケースが含まれている
