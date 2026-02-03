# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、tmuxセッション内で独立したpiインスタンスを起動するスキルです。並列開発に最適化されています。

## 特徴

- **マルチエージェント対応**: Pi、Claude Code、OpenCode、カスタムエージェントに対応
- **自動worktree作成**: Issue番号からブランチ名を自動生成
- **tmux統合**: バックグラウンドでエージェントを実行、いつでもアタッチ可能
- **並列作業**: 複数のIssueを同時に処理
- **簡単なクリーンアップ**: セッションとworktreeを一括削除
- **自動クリーンアップ**: タスク完了時に `###TASK_COMPLETE_<issue_number>###` マーカーを出力すると、外部プロセスが自動的にworktreeとセッションをクリーンアップします

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

# yq (YAML処理、オプション - なくてもフォールバックで動作)
which yq  # オプション
```

## インストール

### スキルとしてインストール（piから使用）

piのスキルディレクトリにクローン:

```bash
git clone https://github.com/takemo101/pi-issue-runner ~/.pi/agent/skills/pi-issue-runner
```

### グローバルインストール（コマンドラインから使用）

任意のディレクトリで `pi-run 42` のようにコマンドを実行できるようにします:

```bash
cd ~/.pi/agent/skills/pi-issue-runner
./install.sh
```

インストールされるコマンド:

| コマンド | 説明 |
|----------|------|
| `pi-run` | Issue実行 |
| `pi-batch` | 複数Issueを依存関係順にバッチ実行 |
| `pi-list` | セッション一覧 |
| `pi-attach` | セッションアタッチ |
| `pi-status` | 状態確認 |
| `pi-stop` | セッション停止 |
| `pi-cleanup` | クリーンアップ |
| `pi-force-complete` | セッション強制完了 |
| `pi-improve` | 継続的改善 |
| `pi-wait` | 完了待機 |
| `pi-watch` | セッション監視 |
| `pi-nudge` | セッションにメッセージ送信 |
| `pi-init` | プロジェクト初期化 |

| オプション | 説明 |
|-----------|------|
| `--ignore-blockers` | 依存関係チェックをスキップして強制実行 |

カスタムインストール先を指定する場合:

```bash
INSTALL_DIR=/usr/local/bin ./install.sh
```

アンインストール:

```bash
./uninstall.sh
```

## 依存関係チェック

`run.sh` はIssue実行前にGitHubネイティブの依存関係（`Blocked by`）をチェックします。

### 動作

- OPENのブロッカーIssueがある場合、実行をスキップしてエラー終了（exit 2）
- ブロッカーのIssue番号とタイトルを表示
- `--ignore-blockers` オプションで強制実行可能

### 例

```bash
$ ./scripts/run.sh 42
[ERROR] Issue #42 is blocked by the following issues:
  - #38: 基盤機能の実装 (OPEN)
[INFO] Complete the blocking issues first, or use --ignore-blockers to force execution.

$ ./scripts/run.sh 42 --ignore-blockers
[WARN] Ignoring blockers and proceeding with Issue #42
...
```

### 終了コード

| コード | 意味 |
|--------|------|
| 2 | Issueがブロックされている |

## 使い方

### プロジェクト初期化

新しいプロジェクトでpi-issue-runnerを使い始める場合：

```bash
# 標準セットアップ（.pi-runner.yaml、.worktrees/、.gitignore更新）
pi-init

# 完全セットアップ（上記 + agents/custom.md、workflows/custom.yaml）
pi-init --full

# 最小セットアップ（.pi-runner.yamlのみ）
pi-init --minimal

# 既存ファイルを上書き
pi-init --force
```

### バッチ実行（依存関係順）

複数のIssueを依存関係を考慮して順次・並列実行：

```bash
# 複数Issueを依存関係順に実行
scripts/run-batch.sh 42 43 44 45

# 実行計画のみ表示
scripts/run-batch.sh 42 43 --dry-run

# 順次実行（並列化しない）
scripts/run-batch.sh 42 43 --sequential

# エラーがあっても続行
scripts/run-batch.sh 42 43 --continue-on-error
```

### Issue実行

```bash
# Issue #42 からworktreeを作成してpiを起動
# pi終了後、自動的にworktreeとセッションがクリーンアップされます
scripts/run.sh 42

# ワークフローを指定して起動（-w は --workflow の短縮形）
scripts/run.sh 42 -w simple            # 簡易ワークフロー（実装・マージのみ）
scripts/run.sh 42 --workflow default   # 完全ワークフロー（デフォルト）

# 利用可能なワークフロー一覧を表示
scripts/run.sh --list-workflows

# 自動アタッチせずにバックグラウンドで起動
scripts/run.sh 42 --no-attach

# pi終了後の自動クリーンアップを無効化
scripts/run.sh 42 --no-cleanup

# カスタムブランチ名で作成（-b は --branch の短縮形）
scripts/run.sh 42 -b custom-feature

# 特定のベースブランチから作成
scripts/run.sh 42 --base develop

# 既存セッションがあればアタッチ
scripts/run.sh 42 --reattach

# 既存セッション/worktreeを削除して再作成
scripts/run.sh 42 --force

# エージェントに追加の引数を渡す
scripts/run.sh 42 --agent-args "--verbose"
# または従来のオプション（後方互換性）
scripts/run.sh 42 --pi-args "--verbose"
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

プロジェクトルートに `.pi-runner.yaml` を作成して動作をカスタマイズできます：

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

# pi設定（後方互換性あり）
pi:
  command: "pi"
  args: []

# GitHub設定
github:
  include_comments: true  # Issueコメントを含める（デフォルト: true）
  max_comments: 10        # 最大コメント数（0 = 無制限）

# エージェント設定（複数エージェント対応）
agent:
  type: pi  # pi, claude, opencode, custom
  # command: /custom/path/pi
  # args:
  #   - --verbose
```

### 複数エージェント対応

Pi以外のコーディングエージェントを使用できます：

```yaml
# Claude Codeを使用
agent:
  type: claude

# OpenCodeを使用
agent:
  type: opencode

# カスタムエージェント
agent:
  type: custom
  command: my-agent
  template: '{{command}} {{args}} --file "{{prompt_file}}"'
```

環境変数でも設定可能：

```bash
# Claude Codeを一時的に使用
PI_RUNNER_AGENT_TYPE=claude scripts/run.sh 42
```

## ワークフロー例

##### 複数Issueの一括実行

`run-batch.sh` を使用すると、依存関係を考慮して複数のIssueを自動的に実行できます。

```bash
# 複数Issueを一括実行（依存関係順に自動実行）
scripts/run-batch.sh 42 43 44 45 46

# 実行計画のみ表示（実行しない）
scripts/run-batch.sh 42 43 44 --dry-run

# 順次実行（並列実行しない）
scripts/run-batch.sh 42 43 44 --sequential

# エラーがあっても次のレイヤーを継続実行
scripts/run-batch.sh 42 43 44 --continue-on-error

# タイムアウト指定
scripts/run-batch.sh 42 43 44 --timeout 1800
```

**仕組み**:
1. Issue間の依存関係を解析（GitHubの "Blocked by" 関係）
2. 依存関係に基づいて実行レイヤーを計算
3. 同じレイヤー内のIssueを並列実行
4. 前のレイヤーが完了してから次のレイヤーを実行

**詳細**: [docs/parallel-execution.md](docs/parallel-execution.md#run-batchsh-の使用)

### 複数Issueの並列作業（手動）

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

piセッション内で `###TASK_COMPLETE_42###` を出力すると、外部プロセスが自動的にworktreeとセッションをクリーンアップします。

```bash
# 手動でクリーンアップする場合
scripts/cleanup.sh 42
```

### 継続的改善（improve.sh）

プロジェクトのレビュー→Issue作成→並列実行→完了待ちを自動化:

```bash
# 基本的な使い方（最大3イテレーション）
scripts/improve.sh

# オプション指定
scripts/improve.sh --max-iterations 2 --max-issues 3

# ドライラン（レビューのみ、Issue作成・実行しない）
scripts/improve.sh --dry-run

# 自動継続（承認ゲートをスキップ）
scripts/improve.sh --auto-continue

# レビューのみ表示
scripts/improve.sh --review-only
```

### 複数セッションの完了待機

```bash
# 複数のIssueセッションが完了するまで待機
scripts/wait-for-sessions.sh 140 141 144

# タイムアウト指定
scripts/wait-for-sessions.sh 140 141 --timeout 1800

# エラー発生時に即座に終了
scripts/wait-for-sessions.sh 140 141 --fail-fast
```

## ワークフロー

### ビルトインワークフロー

- **default**: 完全ワークフロー（計画→実装→レビュー→マージ）
- **simple**: 簡易ワークフロー（実装→マージのみ）
- **thorough**: 徹底ワークフロー（計画→実装→テスト→レビュー→マージ）
- **ci-fix**: CI修正ワークフロー（CI失敗の自動修正）

```bash
# デフォルトワークフロー
scripts/run.sh 42

# 簡易ワークフロー
scripts/run.sh 42 --workflow simple
```

### カスタムワークフロー

プロジェクト固有のワークフローを定義できます。以下の優先順位で読み込まれます：

1. `.pi-runner.yaml`（プロジェクトルート）
2. `.pi/workflow.yaml`
3. ビルトインワークフロー

ワークフロー定義例:

```yaml
# workflows/custom.yaml
name: custom
description: カスタムワークフロー
steps:
  - plan
  - implement
  - review
  - merge
```

エージェントテンプレートは以下の変数を使用できます:

| 変数 | 説明 |
|------|------|
| `{{issue_number}}` | GitHub Issue番号 |
| `{{issue_title}}` | Issueタイトル |
| `{{branch_name}}` | ブランチ名 |
| `{{worktree_path}}` | worktreeのパス |
| `{{step_name}}` | 現在のステップ名（カスタム用） |
| `{{workflow_name}}` | ワークフロー名（カスタム用） |

## Hook機能

セッションのライフサイクルイベントでカスタムスクリプトを実行できます。

```yaml
# .pi-runner.yaml
hooks:
  on_start: ./hooks/on-start.sh
  on_success: terminal-notifier -title "完了" -message "Issue #{{issue_number}} が完了しました"
  on_error: |
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"text": "Issue #{{issue_number}} でエラー"}' \
      $SLACK_WEBHOOK_URL
  on_cleanup: echo "クリーンアップ完了" >> ~/.pi-runner/activity.log
```

### ⚠️ セキュリティ注意

インラインフックコマンド（文字列として記述されたコマンド）は `eval` で実行されます。`.pi-runner.yaml` に含まれるコマンドが実行されるため、**信頼できないリポジトリの設定ファイルは確認してから実行してください**。

詳細なセキュリティ情報は [docs/security.md](docs/security.md) を参照してください。

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
│   ├── force-complete.sh   # セッション強制完了
│   ├── watch-session.sh    # セッション監視と自動クリーンアップ
│   ├── wait-for-sessions.sh # 複数セッション完了待機
│   ├── improve.sh          # 継続的改善スクリプト
│   ├── init.sh             # プロジェクト初期化
│   └── test.sh             # テスト一括実行
├── lib/
│   ├── agent.sh            # マルチエージェント対応
│   ├── batch.sh            # バッチ処理コア機能
│   ├── ci-classifier.sh    # CI失敗タイプ分類
│   ├── ci-fix.sh           # CI失敗検出・自動修正
│   ├── ci-monitor.sh       # CI状態監視
│   ├── ci-retry.sh         # CI自動修正リトライ管理
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
│   ├── config.sh           # 設定読み込み
│   ├── daemon.sh           # プロセスデーモン化
│   ├── dependency.sh       # 依存関係解析・レイヤー計算
│   ├── github.sh           # GitHub API操作
│   ├── hooks.sh            # イベントhook機能
│   ├── log.sh              # ログ出力
│   ├── notify.sh           # 通知機能
│   ├── status.sh           # ステータスファイル管理
│   ├── template.sh         # テンプレート処理
│   ├── tmux.sh             # tmux操作
│   ├── workflow-finder.sh  # ワークフロー検索
│   ├── workflow-loader.sh  # ワークフロー読み込み
│   ├── workflow-prompt.sh  # プロンプト処理
│   ├── workflow.sh         # ワークフローエンジン
│   ├── worktree.sh         # Git worktree操作
│   └── yaml.sh             # YAMLパーサー
├── workflows/               # ビルトインワークフロー定義
│   ├── ci-fix.yaml         # CI修正ワークフロー
│   ├── default.yaml        # 完全ワークフロー
│   ├── simple.yaml         # 簡易ワークフロー
│   └── thorough.yaml       # 徹底ワークフロー
├── agents/                  # エージェントテンプレート
│   ├── ci-fix.md           # CI修正エージェント
│   ├── plan.md             # 計画エージェント
│   ├── implement.md        # 実装エージェント
│   ├── review.md           # レビューエージェント
│   ├── test.md             # テストエージェント
│   └── merge.md            # マージエージェント
├── docs/                    # ドキュメント
├── test/                    # Batsテスト（*.bats形式）
│   ├── lib/                 # ライブラリのユニットテスト
│   │   ├── agent.bats       # agent.sh のテスト
│   │   ├── ci-classifier.bats   # ci-classifier.sh のテスト
│   │   ├── ci-fix.bats      # ci-fix.sh のテスト
│   │   ├── ci-monitor.bats      # ci-monitor.sh のテスト
│   │   ├── ci-retry.bats        # ci-retry.sh のテスト
│   │   ├── cleanup-orphans.bats  # cleanup-orphans.sh のテスト
│   │   ├── cleanup-plans.bats    # cleanup-plans.sh のテスト
│   │   ├── config.bats      # config.sh のテスト
│   │   ├── github.bats      # github.sh のテスト
│   │   ├── hooks.bats       # hooks.sh のテスト
│   │   ├── log.bats         # log.sh のテスト
│   │   ├── notify.bats      # notify.sh のテスト
│   │   ├── status.bats      # status.sh のテスト
│   │   ├── template.bats    # template.sh のテスト
│   │   ├── tmux.bats        # tmux.sh のテスト
│   │   ├── workflow-finder.bats  # workflow-finder.sh のテスト
│   │   ├── workflow-loader.bats  # workflow-loader.sh のテスト
│   │   ├── workflow-prompt.bats  # workflow-prompt.sh のテスト
│   │   ├── workflow.bats    # workflow.sh のテスト
│   │   ├── worktree.bats    # worktree.sh のテスト
│   │   └── yaml.bats        # yaml.sh のテスト
│   ├── scripts/             # スクリプトの統合テスト
│   ├── regression/          # 回帰テスト
│   ├── fixtures/            # テスト用フィクスチャ
│   └── test_helper.bash     # Bats共通ヘルパー
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
└── .pi-runner.yaml         # 設定ファイル（オプション）
```

## テスト

### セットアップ

```bash
# macOS
brew install bats-core

# Linux (Ubuntu/Debian)
sudo apt install bats
```

### テスト実行

```bash
# 全Batsテストを実行
bats test/lib/*.bats test/scripts/*.bats

# 特定のテストファイルを実行
bats test/lib/config.bats

# 詳細出力で実行
bats --tap test/lib/*.bats
```

### テスト構造

```
test/
├── lib/                         # ライブラリのユニットテスト
│   ├── agent.bats               # agent.sh のテスト
│   ├── ci-classifier.bats       # ci-classifier.sh のテスト
│   ├── ci-fix.bats              # ci-fix.sh のテスト
│   ├── ci-monitor.bats          # ci-monitor.sh のテスト
│   ├── ci-retry.bats            # ci-retry.sh のテスト
│   ├── cleanup-orphans.bats     # cleanup-orphans.sh のテスト
│   ├── cleanup-plans.bats       # cleanup-plans.sh のテスト
│   ├── config.bats              # config.sh のテスト
│   ├── github.bats              # github.sh のテスト
│   ├── hooks.bats               # hooks.sh のテスト
│   ├── log.bats                 # log.sh のテスト
│   ├── notify.bats              # notify.sh のテスト
│   ├── status.bats              # status.sh のテスト
│   ├── template.bats            # template.sh のテスト
│   ├── tmux.bats                # tmux.sh のテスト
│   ├── workflow-finder.bats     # workflow-finder.sh のテスト
│   ├── workflow-loader.bats     # workflow-loader.sh のテスト
│   ├── workflow-prompt.bats     # workflow-prompt.sh のテスト
│   ├── workflow.bats            # workflow.sh のテスト
│   ├── worktree.bats            # worktree.sh のテスト
│   └── yaml.bats                # yaml.sh のテスト
├── scripts/                     # スクリプトの統合テスト
│   ├── attach.bats              # attach.sh のテスト
│   ├── cleanup.bats             # cleanup.sh のテスト
│   ├── force-complete.bats      # force-complete.sh のテスト
│   ├── improve.bats             # improve.sh のテスト
│   ├── init.bats                # init.sh のテスト
│   ├── list.bats                # list.sh のテスト
│   ├── nudge.bats               # nudge.sh のテスト
│   ├── run.bats                 # run.sh のテスト
│   ├── run-batch.bats           # run-batch.sh のテスト
│   ├── status.bats              # status.sh のテスト
│   ├── stop.bats                # stop.sh のテスト
│   ├── test.bats                # test.sh のテスト
│   ├── wait-for-sessions.bats   # wait-for-sessions.sh のテスト
│   └── watch-session.bats       # watch-session.sh のテスト
├── regression/                  # 回帰テスト
│   └── critical-fixes.bats
├── fixtures/                    # テスト用フィクスチャ
│   └── sample-config.yaml
└── test_helper.bash             # Bats共通ヘルパー（モック関数含む）
```

## メンテナンス

定期的なクリーンアップを推奨します。

### 一括クリーンアップ

```bash
# 孤立したステータスファイル + 古い計画書を削除
./scripts/cleanup.sh --all

# 確認のみ（削除しない）
./scripts/cleanup.sh --all --dry-run
```

### 個別クリーンアップ

```bash
# 孤立したステータスファイルを削除
./scripts/cleanup.sh --orphans

# 古い計画書を削除（直近N件を保持、設定: plans.keep_recent）
./scripts/cleanup.sh --rotate-plans

# クローズ済みIssueの計画書を削除
./scripts/cleanup.sh --delete-plans
```

### 手動削除が必要なもの

以下のディレクトリは必要に応じて手動で削除してください：

```bash
# improve.sh のログ
rm -rf .improve-logs/

# 監視プロセスのログ
rm -f /tmp/pi-watcher-*.log
```

### 設定

計画書の保持件数は `.pi-runner.yaml` で設定できます：

```yaml
plans:
  keep_recent: 10  # 直近10件を保持（0 = 全て保持）
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

- [概要](docs/overview.md) - システム全体の概要
- [アーキテクチャ](docs/architecture.md) - システム設計
- [仕様書](docs/SPECIFICATION.md) - 詳細仕様
- [ワークフロー](docs/workflows.md) - ワークフロー定義の詳細
- [Hook機能](docs/hooks.md) - イベントフック詳細
- [Git Worktree管理](docs/worktree-management.md) - worktree運用
- [tmux統合](docs/tmux-integration.md) - tmuxセッション管理
- [並列実行](docs/parallel-execution.md) - 複数タスクの並列処理
- [状態管理](docs/state-management.md) - ステータスファイル管理
- [設定リファレンス](docs/configuration.md) - 設定オプション
- [セキュリティ](docs/security.md) - 入力サニタイズとセキュリティ対策
- [変更履歴](docs/CHANGELOG.md) - バージョン履歴

## 開発

開発に参加する場合は [AGENTS.md](AGENTS.md) を参照してください。

### テスト実行

```bash
# 全テスト実行
./scripts/test.sh

# 特定のテストのみ実行（パターン指定）
./scripts/test.sh config

# 詳細ログ付きで実行
./scripts/test.sh -v

# 最初の失敗で停止（fail-fast）
./scripts/test.sh -f
```

## ライセンス

MIT License - [LICENSE](LICENSE) を参照

<!-- Test comment for auto-cleanup feature verification (Issue #129) -->
