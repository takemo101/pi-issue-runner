# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、tmuxセッション内で独立したpiインスタンスを起動するスキルです。並列開発に最適化されています。

## 特徴

- **自動worktree作成**: Issue番号からブランチ名を自動生成
- **tmux統合**: バックグラウンドでpiを実行、いつでもアタッチ可能
- **並列作業**: 複数のIssueを同時に処理
- **簡単なクリーンアップ**: セッションとworktreeを一括削除

## 前提条件

```bash
# GitHub CLI（認証済み）
gh auth status

# tmux
which tmux

# pi
which pi

# jq (JSON処理)
which jq

# yq (YAML処理、オプション - ワークフローのカスタマイズに必要)
which yq
```

## インストール

piのスキルディレクトリにクローン:

```bash
git clone https://github.com/takemo101/pi-issue-runner ~/.pi/agent/skills/pi-issue-runner
```

## 使い方

### Issue実行

```bash
# Issue #42 からworktreeを作成してpiを起動
# pi終了後、自動的にworktreeとセッションがクリーンアップされます
scripts/run.sh 42

# 自動アタッチせずにバックグラウンドで起動
scripts/run.sh 42 --no-attach

# pi終了後の自動クリーンアップを無効化
scripts/run.sh 42 --no-cleanup

# カスタムブランチ名で作成
scripts/run.sh 42 --branch custom-feature

# 特定のベースブランチから作成
scripts/run.sh 42 --base develop

# 既存セッションがあればアタッチ
scripts/run.sh 42 --reattach

# 既存セッション/worktreeを削除して再作成
scripts/run.sh 42 --force
```

### セッション管理

```bash
# 実行中のセッション一覧
scripts/list.sh

# セッションにアタッチ
scripts/attach.sh pi-issue-42  # または scripts/attach.sh 42

# 状態確認
scripts/status.sh pi-issue-42

# セッションを終了
scripts/stop.sh pi-issue-42

# セッションとworktreeをクリーンアップ
scripts/cleanup.sh pi-issue-42
```

## 設定

プロジェクトルートに `.pi-runner.yml` を作成して動作をカスタマイズできます：

```yaml
# Git worktree設定
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env"
    - ".env.local"

# tmux設定
tmux:
  session_prefix: "pi"
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
scripts/attach.sh 42
```

### 完了後のクリーンアップ

```bash
# PR作成後、worktreeをクリーンアップ
scripts/cleanup.sh 42
```

## ディレクトリ構造

```
pi-issue-runner/
├── SKILL.md                 # スキル定義（piから参照）
├── AGENTS.md                # 開発ガイド
├── README.md                # このファイル
├── scripts/
│   ├── run.sh              # Issue実行
│   ├── list.sh             # セッション一覧
│   ├── status.sh           # 状態確認
│   ├── attach.sh           # セッションアタッチ
│   ├── stop.sh             # セッション停止
│   ├── cleanup.sh          # クリーンアップ
│   └── post-session.sh     # セッション終了後処理
├── lib/
│   ├── config.sh           # 設定読み込み
│   ├── github.sh           # GitHub API操作
│   ├── log.sh              # ログ出力
│   ├── tmux.sh             # tmux操作
│   ├── workflow.sh         # ワークフローエンジン
│   └── worktree.sh         # Git worktree操作
├── docs/                    # ドキュメント
├── test/                    # 単体テスト
├── tests/                   # Batsテスト
└── .worktrees/              # worktree作成先（実行時に生成）
```

実行時に対象プロジェクトに作成されるworktree構造:

```
your-project/
├── .worktrees/
│   ├── issue-42/           # Issue #42 のworktree
│   │   ├── .env            # コピーされたファイル
│   │   └── ...
│   └── issue-43/           # Issue #43 のworktree
│       └── ...
└── .pi-runner.yml          # 設定ファイル（オプション）
```

## トラブルシューティング

### tmuxセッションが見つからない

```bash
# セッション一覧を確認
tmux list-sessions

# セッションを手動で作成
tmux new-session -s pi-issue-42 -d
```

### worktreeが残っている

```bash
# worktreeを手動で削除
git worktree remove .worktrees/issue-42

# または強制削除
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

- [アーキテクチャ](docs/architecture.md) - システム設計
- [Git Worktree管理](docs/worktree-management.md) - worktree運用
- [tmux統合](docs/tmux-integration.md) - tmuxセッション管理
- [並列実行](docs/parallel-execution.md) - 複数タスクの並列処理
- [設定リファレンス](docs/configuration.md) - 設定オプション

## 開発

開発に参加する場合は [AGENTS.md](AGENTS.md) を参照してください。

## ライセンス

MIT License - [LICENSE](LICENSE) を参照
