# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、ターミナルマルチプレクサ（tmux/Zellij）のセッション内で独立したpiインスタンスを起動するスキルです。並列開発に最適化されています。

## 特徴

- **マルチエージェント対応**: Pi、Claude Code、OpenCode、カスタムエージェントに対応
- **自動worktree作成**: Issue番号からブランチ名を自動生成
- **マルチプレクサ対応**: tmuxとZellijの両方をサポート、設定で切り替え可能
- **並列作業**: 複数のIssueを同時に処理
- **簡単なクリーンアップ**: セッションとworktreeを一括削除
- **自動クリーンアップ**: タスク完了時に `###TASK_COMPLETE_<issue_number>###` マーカーを出力すると、外部プロセスが自動的にworktreeとセッションをクリーンアップします

## 動作環境

- **macOS** (Homebrew)
- **Linux** (依存パッケージは手動インストールが必要)

## 前提条件

- **Bash 4.0以上** (macOSの場合: `brew install bash`)
- `gh` (GitHub CLI、認証済み)
- `tmux` または `zellij` (ターミナルマルチプレクサ)
- `pi`
- `jq` (JSON処理)
- `yq` (オプション - YAML解析の精度向上。なくても動作します)

> **Note**: `install.sh --with-deps` は macOS (Homebrew) のみ対応しています。  
> Linux では依存パッケージ（`gh`, `tmux`, `jq`, `yq`）を手動でインストールしてください。

## インストール

### スキルとしてインストール（piから使用）

piのスキルディレクトリにクローン（パスは環境に合わせて変更してください）:

```bash
# 例: ユーザースキルディレクトリ
git clone https://github.com/takemo101/pi-issue-runner ~/.pi/agent/skills/pi-issue-runner

# または: プロジェクト固有のスキルディレクトリ
git clone https://github.com/takemo101/pi-issue-runner .pi/skills/pi-issue-runner
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
| `pi-sweep` | 全セッションのマーカーチェック・cleanup |
| `pi-cleanup` | クリーンアップ |
| `pi-force-complete` | セッション強制完了 |
| `pi-improve` | 継続的改善 |
| `pi-wait` | 完了待機 |
| `pi-watch` | セッション監視 |
| `pi-nudge` | セッションにメッセージ送信 |
| `pi-init` | プロジェクト初期化 |
| `pi-context` | コンテキスト管理 |
| `pi-dashboard` | ダッシュボード表示 |
| `pi-ci-fix` | CI修正ヘルパー |
| `pi-next` | 次のタスク取得 |
| `pi-restart-watcher` | Watcher再起動 |
| `pi-mux-all` | 全セッション表示（タイル表示） |
| `pi-generate-config` | プロジェクト解析・設定生成 |
| `pi-test` | テスト一括実行 |
| `pi-verify-config-docs` | 設定ドキュメントの整合性検証 |

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
# .pi-runner.yaml に workflows セクションがある場合、-w 省略で auto（AI自動選択）
scripts/run.sh 42 -w simple            # 簡易ワークフロー（実装・マージのみ）
scripts/run.sh 42 --workflow default   # 完全ワークフロー
scripts/run.sh 42 -w auto             # AIがIssue内容から最適なワークフローを自動選択

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

# デバッグオプション
scripts/run.sh --show-config           # 現在の設定を表示
scripts/run.sh --list-agents           # 利用可能なエージェント一覧
scripts/run.sh 42 --show-agent-config  # エージェント設定を表示
```

### コンテキスト永続化

pi-issue-runnerは、セッション間でコンテキスト（学習内容、試行履歴、技術的決定事項など）を永続化できます。

#### 自動読み込み

`pi-run` でIssueを実行すると、過去のコンテキストが自動的にプロンプトに注入されます：

```bash
pi-run 42
```

#### コンテキストの確認

```bash
# Issue固有のコンテキストを表示
scripts/context.sh show 42

# プロジェクト全体のコンテキストを表示
scripts/context.sh show-project

# コンテキストがあるIssue一覧
scripts/context.sh list
```

#### コンテキストの追加

```bash
# Issue固有のコンテキストに追記
scripts/context.sh add 42 "JWT認証は依存ライブラリの問題で失敗"

# プロジェクト全体のコンテキストに追記
scripts/context.sh add-project "ShellCheck SC2155を修正する際は変数宣言と代入を分離"
```

#### コンテキストの編集

```bash
# Issue固有のコンテキストをエディタで編集
scripts/context.sh edit 42

# プロジェクト全体のコンテキストをエディタで編集
scripts/context.sh edit-project
```

#### コンテキストのクリーンアップ

```bash
# 30日より古いコンテキストを削除
scripts/context.sh clean --days 30

# Issue固有のコンテキストを削除
scripts/context.sh remove 42

# プロジェクトコンテキストを削除
scripts/context.sh remove-project
```

#### コンテキストファイルの場所

コンテキストは `.worktrees/.context/` に保存されます：

```
.worktrees/
├── .context/
│   ├── project.md           # プロジェクト全体のコンテキスト
│   └── issues/
│       ├── 42.md            # Issue #42 固有のコンテキスト
│       └── ...
```

#### エージェントによる自動保存

エージェントは、タスク完了時に自動的にコンテキストを保存することが推奨されます。
各エージェントテンプレート（`agents/*.md`）に保存手順が記載されています。

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
    - ".envrc"

# マルチプレクサ設定
multiplexer:
  type: "tmux"  # tmux または zellij
  session_prefix: "pi"
  start_in_session: true

# エージェント設定（複数エージェント対応）
agent:
  type: pi  # pi, claude, opencode, custom
  args:
    - --provider
    - anthropic
    - --model
    - claude-sonnet-4-5

# GitHub設定
github:
  include_comments: true  # Issueコメントを含める（デフォルト: true）
  max_comments: 10        # 最大コメント数（0 = 無制限）

# 並列実行設定
parallel:
  max_concurrent: 5  # 同時実行数の上限（0 = 無制限）

# auto ワークフロー選択設定
auto:
  provider: anthropic
  model: claude-haiku-4-5  # 軽量モデル推奨

# 複数ワークフロー定義（-w で指定、省略時は auto）
workflows:
  default:
    description: 標準ワークフロー（計画・実装・レビュー・マージ）
    steps:
      - plan
      - implement
      - review
      - merge
  feature:
    description: 新機能・大規模変更（新関数追加、新スクリプト作成）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    context: |
      Bash 4.0+ / ShellCheck 準拠 / Bats テスト必須
  fix:
    description: バグ修正・リファクタリング・セキュリティ修正
    steps:
      - implement
      - test
      - review
      - merge
  docs:
    description: ドキュメント更新（README, AGENTS.md, docs/ 以下）
    steps:
      - implement
      - merge
  test:
    description: テスト追加・テスト改善
    steps:
      - implement
      - review
      - merge
  quickfix:
    description: typo修正・設定値変更・コメント修正など軽微な変更
    steps:
      - implement
      - merge

  # ワークフロー固有のエージェント設定（グローバルのagent設定を上書き）
  quick-haiku:
    description: 小規模修正（高速・低コスト）
    steps:
      - implement
      - merge
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5  # 軽量モデルでコスト削減

  thorough-opus:
    description: 徹底レビュー（高精度）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    agent:
      type: claude
      args:
        - --model
        - claude-opus-4  # 最高精度モデル

# 計画書設定
plans:
  keep_recent: 10
  dir: "docs/plans"

# improve-logs クリーンアップ設定
improve_logs:
  keep_recent: 10    # 直近N件のログを保持（0=全て保持）
  keep_days: 7       # N日以内のログを保持（0=日数制限なし）
  dir: .improve-logs # ログディレクトリ
```

### マルチプレクサの切り替え

tmuxとZellijを切り替えて使用できます：

```yaml
# .pi-runner.yaml
multiplexer:
  type: zellij  # tmux から zellij に切り替え
```

環境変数でも設定可能：

```bash
# Zellijを一時的に使用
PI_RUNNER_MULTIPLEXER_TYPE=zellij scripts/run.sh 42

# 全セッションをタイル表示
pi-mux-all -w
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

### ワークフローごとのエージェント設定

ワークフローごとに異なるエージェントやモデルを指定できます。タスクの性質に応じて最適なエージェントを使い分けることが可能です。

ワークフローに `agent` を指定しない場合は、グローバルの `agent` 設定がデフォルトとして使用されます。

**優先順位**: ワークフロー固有の `agent` > グローバルの `agent` > 従来の `pi` 設定

```yaml
# グローバル設定（デフォルト）
agent:
  type: pi
  args:
    - --model
    - claude-sonnet-4-20250514

workflows:
  # 小規模修正: 軽量モデルで高速・低コスト
  quick:
    description: 小規模修正
    steps: [implement, merge]
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5

  # 徹底レビュー: 最高精度モデル
  thorough:
    description: 大規模機能開発
    steps: [plan, implement, test, review, merge]
    agent:
      type: claude
      args:
        - --model
        - claude-opus-4

  # agent未指定 → グローバルのagent設定を使用
  simple:
    description: 簡単な修正
    steps: [implement, merge]
```

詳細は [docs/workflows.md](docs/workflows.md#agent-フィールド-ワークフロー固有のエージェント設定) を参照してください。

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

# AIによる自動選択
scripts/run.sh 42 -w auto
```

### 複数ワークフロー定義

`.pi-runner.yaml` の `workflows` セクションで、用途別の名前付きワークフローを定義できます：

```yaml
# .pi-runner.yaml
workflows:
  default:
    description: 標準ワークフロー（計画・実装・レビュー・マージ）
    steps:
      - plan
      - implement
      - review
      - merge

  feature:
    description: 新機能・大規模変更（新関数追加、新スクリプト作成）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    context: |
      ## 技術スタック
      - Bash 4.0+ / ShellCheck 準拠
      - テスト: Bats (Bash Automated Testing System)
      ## 方針
      - 新しい lib/ には対応する test/lib/*.bats を必ず作成
      - AGENTS.md のディレクトリ構造を更新すること

  fix:
    description: バグ修正・リファクタリング・セキュリティ修正
    steps:
      - implement
      - test
      - review
      - merge

  docs:
    description: ドキュメント更新（README, AGENTS.md, docs/ 以下）
    steps:
      - implement
      - merge

  test:
    description: テスト追加・テスト改善
    steps:
      - implement
      - review
      - merge

  quickfix:
    description: typo修正・設定値変更・コメント修正など軽微な変更
    steps:
      - implement
      - merge
```

```bash
# 名前付きワークフローを指定
scripts/run.sh 42 -w feature
scripts/run.sh 43 -w fix
scripts/run.sh 44 -w quickfix
```

#### `context` フィールド

各ワークフローの `context` フィールドに、技術スタックやコーディング方針などを自由に記述できます。この内容はエージェントのプロンプトに「ワークフローコンテキスト」として注入されます。

#### AIによるワークフロー自動選択（`-w auto`）

`-w auto` を指定すると（`workflows` セクション定義時は省略でも自動適用）、AIがIssueの内容から最適なワークフローを事前選択し、そのワークフローの具体的なステップ（`agents/*.md`）が展開されたプロンプトを生成します：

```bash
scripts/run.sh 42 -w auto
# または workflows セクションがあれば省略可
scripts/run.sh 42
```

**選択の流れ（3段階フォールバック）:**

1. **AI選択** — `pi --print` + 軽量モデル（haiku）で高速にワークフロー名を判定
2. **ルールベース** — Issueタイトルのプレフィックス（`feat:` / `fix:` / `docs:` / `test:` 等）で判定
3. **フォールバック** — 上記いずれも失敗した場合は `default`

**設定（`.pi-runner.yaml`）:**

```yaml
auto:
  provider: anthropic                # AIプロバイダー
  model: claude-haiku-4-5-20250218   # 軽量モデル推奨
```

### カスタムワークフロー（ファイルベース）

ファイルベースのカスタムワークフローも引き続きサポートしています。以下の優先順位で読み込まれます：

1. `.pi-runner.yaml` の `workflows` セクション（名前付き）
2. `.pi-runner.yaml` の `workflow` セクション（デフォルト、後方互換）
3. `.pi/workflow.yaml`
4. ビルトインワークフロー（`workflows/*.yaml`）

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
  on_success: terminal-notifier -title "完了" -message "Issue #$PI_ISSUE_NUMBER が完了しました"
  on_error: |
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"text": "Issue #$PI_ISSUE_NUMBER でエラー"}' \
      $SLACK_WEBHOOK_URL
  on_cleanup: echo "クリーンアップ完了" >> ~/.pi-runner/activity.log
```

### 利用可能な環境変数

hookスクリプトには以下の環境変数が渡されます：

| 環境変数 | 説明 |
|----------|------|
| `PI_ISSUE_NUMBER` | Issue番号 |
| `PI_ISSUE_TITLE` | Issueタイトル |
| `PI_SESSION_NAME` | セッション名 |
| `PI_BRANCH_NAME` | ブランチ名 |
| `PI_WORKTREE_PATH` | worktreeパス |
| `PI_ERROR_MESSAGE` | エラーメッセージ（on_errorのみ） |
| `PI_EXIT_CODE` | 終了コード |

### ⚠️ セキュリティ注意

**デフォルトでインラインhookコマンドは無効化されています。**

インラインhookコマンド（文字列として記述されたコマンド）を使用するには、環境変数を設定してください：

```bash
export PI_RUNNER_ALLOW_INLINE_HOOKS=true
```

ファイルパスで指定されたhookスクリプトは常に実行されます。セキュリティの観点から、インラインコマンドの代わりにスクリプトファイルを使用することを推奨します。

詳細なセキュリティ情報は [docs/security.md](docs/security.md) および [docs/hooks.md](docs/hooks.md) を参照してください。

## ディレクトリ構造

```
pi-issue-runner/
├── SKILL.md                 # スキル定義（piから参照）
├── AGENTS.md                # 開発ガイド
├── README.md                # このファイル
├── scripts/
│   ├── run.sh              # Issue実行
│   ├── run-batch.sh        # 複数Issueを依存関係順にバッチ実行
│   ├── restart-watcher.sh  # Watcher再起動
│   ├── list.sh             # セッション一覧
│   ├── status.sh           # 状態確認
│   ├── attach.sh           # セッションアタッチ
│   ├── stop.sh             # セッション停止
│   ├── sweep.sh            # 全セッションのマーカーチェック・cleanup
│   ├── mux-all.sh          # 全セッション表示（マルチプレクサ対応）
│   ├── cleanup.sh          # クリーンアップ
│   ├── ci-fix-helper.sh    # CI修正ヘルパー（lib/ci-fix.shのラッパー）
│   ├── context.sh          # コンテキスト管理
│   ├── dashboard.sh        # ダッシュボード表示
│   ├── generate-config.sh  # プロジェクト解析・設定生成
│   ├── force-complete.sh   # セッション強制完了
│   ├── next.sh             # 次のタスク取得
│   ├── nudge.sh            # セッションへメッセージ送信
│   ├── watch-session.sh    # セッション監視と自動クリーンアップ
│   ├── wait-for-sessions.sh # 複数セッション完了待機
│   ├── improve.sh          # 継続的改善スクリプト
│   ├── init.sh             # プロジェクト初期化
│   ├── test.sh             # テスト一括実行
│   └── verify-config-docs.sh  # 設定ドキュメントの整合性検証
├── lib/
│   ├── agent.sh            # マルチエージェント対応
│   ├── batch.sh            # バッチ処理コア機能
│   ├── ci-classifier.sh    # CI失敗タイプ分類
│   ├── ci-fix.sh           # CI失敗検出・自動修正（ci-fix-helper.sh経由で使用）
│   ├── ci-monitor.sh       # CI状態監視
│   ├── ci-retry.sh         # CI自動修正リトライ管理
│   ├── cleanup-improve-logs.sh  # improve-logsのクリーンアップ
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
│   ├── config.sh           # 設定読み込み
│   ├── context.sh          # コンテキスト管理
│   ├── daemon.sh           # プロセスデーモン化
│   ├── dashboard.sh        # ダッシュボード機能
│   ├── dependency.sh       # 依存関係解析・レイヤー計算
│   ├── github.sh           # GitHub CLI操作
│   ├── hooks.sh            # イベントhook機能
│   ├── improve.sh          # 継続的改善ライブラリ（オーケストレーター）
│   ├── improve/            # 継続的改善モジュール群
│   │   ├── args.sh         # 引数解析
│   │   ├── deps.sh         # 依存関係チェック
│   │   ├── env.sh          # 環境セットアップ
│   │   ├── execution.sh    # 実行・監視フェーズ
│   │   └── review.sh       # レビューフェーズ
│   ├── log.sh              # ログ出力
│   ├── marker.sh           # マーカー検出ユーティリティ
│   ├── notify.sh           # 通知機能
│   ├── priority.sh         # 優先度計算
│   ├── session-resolver.sh # セッション名解決ユーティリティ
│   ├── status.sh           # ステータスファイル管理
│   ├── template.sh         # テンプレート処理
│   ├── tmux.sh             # マルチプレクサ操作（後方互換ラッパー）
│   ├── multiplexer.sh      # マルチプレクサ抽象化レイヤー
│   ├── multiplexer-tmux.sh # tmux実装
│   ├── multiplexer-zellij.sh # Zellij実装
│   ├── workflow-finder.sh  # ワークフロー検索
│   ├── workflow-loader.sh  # ワークフロー読み込み
│   ├── workflow-prompt.sh  # プロンプト処理
│   ├── workflow-selector.sh # ワークフロー自動選択（auto モード）
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
│   ├── test.md             # テストエージェント
│   ├── review.md           # レビューエージェント
│   └── merge.md            # マージエージェント
├── docs/                    # ドキュメント
├── test/                    # Batsテスト（*.bats形式）
│   ├── lib/                 # ライブラリのユニットテスト
│   │   ├── agent.bats       # agent.sh のテスト
│   │   ├── batch.bats       # batch.sh のテスト
│   │   ├── ci-classifier.bats   # ci-classifier.sh のテスト
│   │   ├── ci-fix.bats      # ci-fix.sh のテスト
│   │   ├── ci-monitor.bats      # ci-monitor.sh のテスト
│   │   ├── ci-retry.bats        # ci-retry.sh のテスト
│   │   ├── cleanup-improve-logs.bats  # cleanup-improve-logs.sh のテスト
│   │   ├── cleanup-orphans.bats  # cleanup-orphans.sh のテスト
│   │   ├── cleanup-plans.bats    # cleanup-plans.sh のテスト
│   │   ├── config.bats      # config.sh のテスト
│   │   ├── context.bats     # context.sh のテスト
│   │   ├── daemon.bats      # daemon.sh のテスト
│   │   ├── dashboard.bats   # dashboard.sh のテスト
│   │   ├── dependency.bats  # dependency.sh のテスト
│   │   ├── github.bats      # github.sh のテスト
│   │   ├── hooks.bats       # hooks.sh のテスト
│   │   ├── log.bats         # log.sh のテスト
│   │   ├── notify.bats      # notify.sh のテスト
│   │   ├── priority.bats    # priority.sh のテスト
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
│   │   ├── applescript-injection.bats
│   │   ├── cleanup-race-condition.bats
│   │   ├── config-master-table-dry.bats
│   │   ├── critical-fixes.bats
│   │   ├── eval-injection.bats
│   │   ├── hooks-env-sanitization.bats
│   │   ├── issue-1066-spaces-in-filenames.bats
│   │   ├── issue-1129-session-label-arg.bats
│   │   ├── multiline-json-grep.bats
│   │   ├── pr-merge-timeout.bats
│   │   └── workflow-name-template.bats
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
│   ├── batch.bats               # batch.sh のテスト
│   ├── ci-classifier.bats       # ci-classifier.sh のテスト
│   ├── ci-fix.bats              # ci-fix.sh のテスト
│   ├── ci-monitor.bats          # ci-monitor.sh のテスト
│   ├── ci-retry.bats            # ci-retry.sh のテスト
│   ├── cleanup-improve-logs.bats # cleanup-improve-logs.sh のテスト
│   ├── cleanup-orphans.bats     # cleanup-orphans.sh のテスト
│   ├── cleanup-plans.bats       # cleanup-plans.sh のテスト
│   ├── config.bats              # config.sh のテスト
│   ├── context.bats             # context.sh のテスト
│   ├── daemon.bats              # daemon.sh のテスト
│   ├── dashboard.bats           # dashboard.sh のテスト
│   ├── dependency.bats          # dependency.sh のテスト
│   ├── github.bats              # github.sh のテスト
│   ├── hooks.bats               # hooks.sh のテスト
│   ├── log.bats                 # log.sh のテスト
│   ├── marker.bats              # marker.sh のテスト
│   ├── notify.bats              # notify.sh のテスト
│   ├── priority.bats            # priority.sh のテスト
│   ├── session-resolver.bats    # session-resolver.sh のテスト
│   ├── status.bats              # status.sh のテスト
│   ├── template.bats            # template.sh のテスト
│   ├── tmux.bats                # tmux.sh のテスト
│   ├── multiplexer.bats         # multiplexer.sh のテスト
│   ├── multiplexer-tmux.bats    # multiplexer-tmux.sh のテスト
│   ├── multiplexer-zellij.bats  # multiplexer-zellij.sh のテスト
│   ├── workflow-finder.bats     # workflow-finder.sh のテスト
│   ├── workflow-loader.bats     # workflow-loader.sh のテスト
│   ├── workflow-prompt.bats     # workflow-prompt.sh のテスト
│   ├── workflow-selector.bats   # workflow-selector.sh のテスト
│   ├── workflow.bats            # workflow.sh のテスト
│   ├── worktree.bats            # worktree.sh のテスト
│   └── yaml.bats                # yaml.sh のテスト
├── scripts/                     # スクリプトの統合テスト
│   ├── attach.bats              # attach.sh のテスト
│   ├── ci-fix-helper.bats       # ci-fix-helper.sh のテスト
│   ├── cleanup.bats             # cleanup.sh のテスト
│   ├── context.bats             # context.sh のテスト
│   ├── dashboard.bats           # dashboard.sh のテスト
│   ├── force-complete.bats      # force-complete.sh のテスト
│   ├── generate-config.bats     # generate-config.sh のテスト
│   ├── improve.bats             # improve.sh のテスト
│   ├── init.bats                # init.sh のテスト
│   ├── list.bats                # list.sh のテスト
│   ├── mux-all.bats             # mux-all.sh のテスト
│   ├── next.bats                # next.sh のテスト
│   ├── nudge.bats               # nudge.sh のテスト
│   ├── restart-watcher.bats     # restart-watcher.sh のテスト
│   ├── run.bats                 # run.sh のテスト
│   ├── run-batch.bats           # run-batch.sh のテスト
│   ├── status.bats              # status.sh のテスト
│   ├── stop.bats                # stop.sh のテスト
│   ├── sweep.bats               # sweep.sh のテスト
│   ├── test.bats                # test.sh のテスト
│   ├── verify-config-docs.bats  # verify-config-docs.sh のテスト
│   ├── wait-for-sessions.bats   # wait-for-sessions.sh のテスト
│   └── watch-session.bats       # watch-session.sh のテスト
├── regression/                  # 回帰テスト
│   ├── applescript-injection.bats
│   ├── cleanup-race-condition.bats
│   ├── config-master-table-dry.bats
│   ├── critical-fixes.bats
│   ├── eval-injection.bats
│   ├── hooks-env-sanitization.bats
│   ├── issue-1066-spaces-in-filenames.bats
│   ├── issue-1129-session-label-arg.bats
│   ├── multiline-json-grep.bats
│   ├── pr-merge-timeout.bats
│   └── workflow-name-template.bats
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

# improve-logsディレクトリのクリーンアップ
./scripts/cleanup.sh --improve-logs

# 日数指定でクリーンアップ
./scripts/cleanup.sh --improve-logs --age 7
```

### 手動削除が必要なもの

以下は必要に応じて手動で削除してください：

```bash
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

### セッションが見つからない

```bash
# tmuxの場合
tmux list-sessions

# Zellijの場合
zellij list-sessions

# セッションを手動で作成（tmux）
tmux new-session -s pi-issue-42 -d

# セッションを手動で作成（Zellij）
zellij -s pi-issue-42
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
- [公開API](docs/public-api.md) - 外部から利用可能なライブラリ関数
- [ワークフロー](docs/workflows.md) - ワークフロー定義の詳細
- [Hook機能](docs/hooks.md) - イベントフック詳細
- [Git Worktree管理](docs/worktree-management.md) - worktree運用
- [マルチプレクサ統合](docs/multiplexer-integration.md) - tmux/Zellijセッション管理
- [並列実行](docs/parallel-execution.md) - 複数タスクの並列処理
- [状態管理](docs/state-management.md) - ステータスファイル管理
- [設定リファレンス](docs/configuration.md) - 設定オプション
- [セキュリティ](docs/security.md) - 入力サニタイズとセキュリティ対策
- [コーディング規約](docs/coding-standards.md) - 開発ガイドライン
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
