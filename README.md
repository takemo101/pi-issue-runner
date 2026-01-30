# Pi Issue Runner

GitHub Issue-driven parallel task runner with Git worktree and tmux integration for pi-mono.

## 概要

GitHub Issueを入力として、Git worktreeを作成し、tmuxセッション内で独立したpiインスタンスを起動します。複数のIssueを並列処理できます。

```
GitHub Issue → Git worktree作成 → tmuxセッション → pi起動 → タスク実行
                                        ↓
                                   並列実行可能
```

## 特徴

- ✅ **GitHub Issue統合** - Issue番号から自動でタスクを取得
- ✅ **Git worktree管理** - 各タスクを独立した作業環境で実行
- ✅ **tmux統合** - セッションベースで管理、アタッチ/デタッチ自由
- ✅ **並列実行** - 複数のIssueを同時に処理
- ✅ **状態管理** - タスクの進捗を追跡・表示
- ✅ **自動クリーンアップ** - 完了したworktreeとセッションの削除

## インストール

### 前提条件

- [Bun](https://bun.sh/) 1.0以上
- [GitHub CLI](https://cli.github.com/) (`gh`) - 認証済み
- [tmux](https://github.com/tmux/tmux)
- [pi-mono](https://github.com/badlogic/pi-mono)

```bash
# 前提条件の確認
gh auth status
which tmux
which pi
```

### インストール方法

```bash
# リポジトリをクローン
git clone https://github.com/takemo101/pi-issue-runner.git
cd pi-issue-runner

# 依存関係をインストール
bun install

# バイナリをビルド（推奨）
bun run build:binary

# グローバルにインストール（オプション）
sudo mv pi-run /usr/local/bin/
```

## クイックスタート

```bash
# Issue #42 を実行
pi-run run --issue 42

# 複数Issueを並列実行
pi-run run --issues 42,43,44

# 実行中のタスク一覧
pi-run list

# タスクの状態を監視
pi-run status --watch

# セッションにアタッチ
pi-run attach pi-issue-42

# クリーンアップ
pi-run cleanup --all
```

## 使い方

### 基本コマンド

#### `run` - タスクを実行

```bash
# 単一Issue
pi-run run --issue 42

# 複数Issue（並列実行）
pi-run run --issues 42,43,44

# バックグラウンドで実行（自動アタッチしない）
pi-run run --issue 42 --no-attach

# カスタムブランチ名
pi-run run --issue 42 --branch feature/custom-name

# 特定のベースブランチから作成
pi-run run --issue 42 --base develop

# piコマンドに追加オプションを渡す
pi-run run --issue 42 --pi-args "--verbose --model claude-sonnet-4"
```

#### `list` - セッション一覧

```bash
# 実行中のセッション一覧
pi-run list

# 詳細表示
pi-run list --verbose
```

#### `status` - タスク状態表示

```bash
# 全タスクの状態
pi-run status

# リアルタイム監視
pi-run status --watch

# 特定タスクの詳細
pi-run status --task pi-issue-42
```

#### `logs` - ログ表示

```bash
# 特定タスクのログ
pi-run logs --task pi-issue-42

# リアルタイムでログを表示
pi-run logs --task pi-issue-42 --follow

# 最後の50行を表示
pi-run logs --task pi-issue-42 --lines 50
```

#### `attach` - セッションにアタッチ

```bash
# セッションにアタッチ
pi-run attach pi-issue-42
```

#### `stop` - タスクを停止

```bash
# 特定タスクを停止
pi-run stop --task pi-issue-42

# 全タスクを停止
pi-run stop --all
```

#### `cleanup` - クリーンアップ

```bash
# 特定タスクをクリーンアップ（worktree + セッション）
pi-run cleanup --task pi-issue-42

# 完了済みタスクを全てクリーンアップ
pi-run cleanup --completed

# 全タスクをクリーンアップ
pi-run cleanup --all --force
```

## 設定

プロジェクトルートに `.pi-runner.yml` を作成すると、動作をカスタマイズできます：

```yaml
# Git worktree設定
worktree:
  base_dir: ".worktrees"        # worktreeの作成先ディレクトリ
  copy_files:                   # worktree作成時にコピーするファイル
    - ".env"
    - ".env.local"
    - "config/local.json"

# tmux設定
tmux:
  session_prefix: "pi-issue"    # セッション名のプレフィックス
  start_in_session: true        # 作成後、自動でアタッチするか

# pi設定
pi:
  command: "pi"                 # piコマンドのパス
  args: []                      # 追加の引数（例: ["--verbose"]）

# 並列実行設定
parallel:
  max_concurrent: 5             # 最大同時実行数
  auto_cleanup: true            # 完了後に自動クリーンアップ
```

## ディレクトリ構造

```
your-project/
├── .worktrees/
│   ├── issue-42/           # Issue #42 のworktree
│   │   ├── .env            # コピーされたファイル
│   │   └── ...
│   └── issue-43/           # Issue #43 のworktree
│       └── ...
├── .pi-runner/
│   ├── tasks.json          # タスク状態管理
│   └── logs/
│       ├── issue-42.log
│       └── issue-43.log
└── .pi-runner.yml          # 設定ファイル（オプション）
```

## ワークフロー例

### 複数Issueの並列開発

```bash
# 3つのIssueを同時に起動
pi-run run --issues 42,43,44 --no-attach

# 状態を確認
pi-run status

# 特定のセッションにアタッチして作業
pi-run attach pi-issue-42

# デタッチ（Ctrl+B → D）

# 別のセッションにアタッチ
pi-run attach pi-issue-43

# 完了したタスクをクリーンアップ
pi-run cleanup --completed
```

### リアルタイム監視

```bash
# ターミナル1: タスクを実行
pi-run run --issues 42,43,44 --no-attach

# ターミナル2: 状態を監視
pi-run status --watch

# ターミナル3: ログをストリーミング
pi-run logs --task pi-issue-42 --follow
```

## 開発

```bash
# 依存関係をインストール
bun install

# 開発モードで実行
bun run dev run --issue 42

# テスト
bun test

# 型チェック
bun run typecheck

# ビルド
bun run build

# バイナリビルド
bun run build:binary
```

## アーキテクチャ

```
src/
├── cli.ts              # CLIエントリーポイント
├── commands/
│   ├── run.ts          # Issue実行
│   ├── list.ts         # セッション一覧
│   ├── status.ts       # 状態監視
│   ├── logs.ts         # ログ表示
│   ├── attach.ts       # セッションアタッチ
│   ├── stop.ts         # セッション停止
│   └── cleanup.ts      # クリーンアップ
├── core/
│   ├── worktree.ts     # Git worktree管理
│   ├── tmux.ts         # tmuxセッション管理
│   ├── github.ts       # GitHub API
│   ├── task-manager.ts # タスク状態管理
│   └── config.ts       # 設定読み込み
└── utils/
    ├── logger.ts       # ロガー
    └── types.ts        # 型定義
```

## トラブルシューティング

### tmuxセッションが見つからない

```bash
# セッション一覧を確認
tmux list-sessions

# pi-runで確認
pi-run list
```

### worktreeが残っている

```bash
# worktreeを手動で削除
git worktree remove .worktrees/issue-42

# 強制削除
git worktree remove --force .worktrees/issue-42
```

### GitHub Issueが取得できない

```bash
# GitHub CLIの認証を確認
gh auth status

# 再認証
gh auth login
```

## ドキュメント

詳細な仕様とアーキテクチャは [docs/](./docs/) を参照してください：

- **[仕様書](./docs/SPECIFICATION.md)** - 全体仕様概要
- **[アーキテクチャ](./docs/architecture.md)** - システム設計
- **[Worktree管理](./docs/worktree-management.md)** - Git worktree機能
- **[Tmux統合](./docs/tmux-integration.md)** - セッション管理
- **[並列実行](./docs/parallel-execution.md)** - 並列処理の仕様
- **[状態管理](./docs/state-management.md)** - データ永続化
- **[設定](./docs/configuration.md)** - 設定ガイド

## ライセンス

MIT

## 謝辞

このプロジェクトは [orchestrator-hybrid](https://github.com/takemo101/orchestrator-hybrid) と [pi-mono](https://github.com/badlogic/pi-mono) にインスパイアされています。
