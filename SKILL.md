---
name: pi-issue-runner
description: GitHub IssueからGit worktreeを作成し、tmuxセッション内で別のpiインスタンスを起動してタスクを実行します。並列開発に最適。
---

# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、tmuxセッション内で独立したpiインスタンスを起動します。

## 前提条件

```bash
# 必須ツール
gh auth status    # GitHub CLI（認証済み）
which tmux        # tmux
which pi          # pi-mono
```

## 基本的な使い方

### Issue実行

```bash
# Issue #42 からworktreeを作成してpiを起動
scripts/run.sh 42

# 自動アタッチせずにバックグラウンドで起動
scripts/run.sh 42 --no-attach

# カスタムブランチ名で作成
scripts/run.sh 42 --branch custom-feature-name

# 特定のベースブランチから作成
scripts/run.sh 42 --base develop
```

### セッション管理

```bash
# 実行中のセッション一覧
scripts/list.sh

# セッションにアタッチ
scripts/attach.sh pi-issue-42

# セッションを終了
scripts/stop.sh pi-issue-42

# 状態確認
scripts/status.sh pi-issue-42

# セッションとworktreeをクリーンアップ
scripts/cleanup.sh pi-issue-42
```

## 設定

プロジェクトルートに `.pi-issue-runner.yml` を作成して動作をカスタマイズできます：

```yaml
# Git worktree設定
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env"
    - ".env.local"

# tmux設定
tmux:
  session_prefix: "pi-issue"
  start_in_session: true

# pi設定
pi:
  command: "pi"
  args: []
```

## ワークフロー例

### 複数Issueの並列作業

```bash
# 複数のIssueをバックグラウンドで起動
scripts/run.sh 42 --no-attach
scripts/run.sh 43 --no-attach
scripts/run.sh 44 --no-attach

# 一覧確認
scripts/list.sh

# 必要に応じてアタッチ
scripts/attach.sh pi-issue-42
```

### 完了後のクリーンアップ

```bash
# PR作成後、worktreeをクリーンアップ
scripts/cleanup.sh pi-issue-42
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
└── .pi-issue-runner.yml    # 設定ファイル（オプション）
```

## トラブルシューティング

詳細は [docs/](docs/) を参照してください。
