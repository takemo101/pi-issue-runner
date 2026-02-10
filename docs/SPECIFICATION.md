# Pi Issue Runner - 仕様書

## 概要

Pi Issue RunnerはGitHub Issueを入力として、Git worktreeとマルチプレクサセッション（tmux/Zellij）を活用して複数のpiインスタンスを並列実行するタスクランナーです。

## 目的

- GitHub Issueベースの開発ワークフローを自動化
- 複数のタスクを独立した環境で並列実行
- 開発者がセッション間を自由に移動できる柔軟性の提供
- piエージェントの実行環境を分離し、干渉を防ぐ

## 主要機能

### 1. GitHub Issue統合

- GitHub CLI (`gh`) を使用してIssueを取得
- Issue番号から自動的にタスク情報を抽出
- Issue番号をpiのプロンプトとして使用

### 2. Git Worktree管理

- 各Issue専用のworktreeを自動作成
- ブランチ名はIssue番号とタイトルから自動生成（例: `feature/issue-42-bug-fix`）
- 必要なファイル（.env等）を自動コピー
- タスク完了後のクリーンアップ（オプションでブランチも削除）

### 3. マルチプレクサセッション統合

- 各タスクを独立したマルチプレクサセッション（tmux/Zellij）内で実行
- セッション名: `{prefix}-issue-{番号}` (例: `pi-issue-42`)
- アタッチ/デタッチによる柔軟なセッション管理
- バックグラウンド実行のサポート

### 4. Pi実行制御

- Worktree内で独立したpiインスタンスを起動
- Issue番号を自動的にプロンプトとして渡す
- piコマンドへのカスタム引数サポート

### 5. 並列実行

- 複数のIssueを同時に処理
- 各タスクは完全に独立した環境で実行
- 最大同時実行数の設定（`parallel.max_concurrent`）

### 6. クリーンアップ

- **自動クリーンアップ（デフォルト）**: pi終了後、worktreeとセッションを自動削除
- `--no-cleanup`オプションで自動クリーンアップを無効化
- 手動クリーンアップ: `cleanup.sh`でworktreeとセッションを削除
- ブランチの削除（`--delete-branch`オプション）
- バックグラウンド実行（`--no-attach`）との併用サポート

## コアコンセプト

### 実行フロー

```
Issue番号入力
    ↓
GitHub Issueを取得（gh issue view）
    ↓
Git Worktreeを作成（git worktree add）
    ↓
必要なファイルをコピー（.env等）
    ↓
マルチプレクサセッションを作成（tmux/Zellij）
    ↓
.pi-prompt.mdを生成（Issue情報を埋め込み）
    ↓
セッション内でpiを起動（pi @.pi-prompt.md）
    ↓
pi終了後、自動クリーンアップ実行（--no-cleanup指定時は省略）
```

### ディレクトリ構造

```
project-root/
├── .worktrees/              # Worktree作業ディレクトリ
│   ├── issue-42-xxx/        # Issue #42のworktree
│   │   ├── .env             # コピーされた設定ファイル
│   │   ├── src/
│   │   └── ...
│   └── issue-43-yyy/        # Issue #43のworktree
│       └── ...
├── .pi-runner.yaml          # ユーザー設定
├── workflows/               # ビルトインワークフロー
│   ├── ci-fix.yaml          # CI修正ワークフロー
│   ├── default.yaml         # 完全ワークフロー
│   ├── simple.yaml          # 簡易ワークフロー
│   └── thorough.yaml        # 徹底ワークフロー
├── agents/                  # エージェントテンプレート
│   ├── ci-fix.md            # CI修正エージェント
│   ├── improve-review.md    # improve.sh レビュープロンプト（カスタマイズ可能）
│   ├── plan.md              # 計画エージェント
│   ├── implement.md         # 実装エージェント
│   ├── review.md            # レビューエージェント
│   ├── test.md              # テストエージェント
│   └── merge.md             # マージエージェント
├── lib/                     # シェルスクリプトライブラリ
│   ├── agent.sh             # マルチエージェント対応
│   ├── batch.sh             # バッチ処理コア機能
│   ├── ci-classifier.sh     # CI失敗タイプ分類
│   ├── ci-fix.sh            # CI失敗検出・自動修正
│   ├── ci-fix/              # CI修正サブモジュール群
│   │   ├── bash.sh          # Bash固有の修正・検証ロジック
│   │   ├── common.sh        # 共通ユーティリティ
│   │   ├── detect.sh        # プロジェクトタイプ検出
│   │   ├── escalation.sh    # エスカレーション処理
│   │   ├── go.sh            # Go固有の修正・検証ロジック
│   │   ├── node.sh          # Node固有の修正・検証ロジック
│   │   ├── python.sh        # Python固有の修正・検証ロジック
│   │   └── rust.sh          # Rust固有の修正・検証ロジック
│   ├── ci-monitor.sh        # CI状態監視
│   ├── ci-retry.sh          # CI自動修正リトライ管理
│   ├── cleanup-improve-logs.sh # 改善ログのクリーンアップ
│   ├── cleanup-orphans.sh   # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh     # 計画書のローテーション
│   ├── cleanup-trap.sh      # エラー時クリーンアップトラップ管理
│   ├── config.sh            # 設定管理
│   ├── context.sh           # コンテキスト管理
│   ├── daemon.sh            # プロセスデーモン化
│   ├── dashboard.sh         # ダッシュボード機能
│   ├── dependency.sh        # 依存関係解析・レイヤー計算
│   ├── generate-config.sh   # プロジェクト解析・設定生成（ライブラリ関数）
│   ├── github.sh            # GitHub CLI操作
│   ├── hooks.sh             # Hook機能
│   ├── improve.sh           # 継続的改善ライブラリ（オーケストレーター）
│   ├── improve/             # 継続的改善モジュール群
│   │   ├── args.sh          # 引数解析
│   │   ├── deps.sh          # 依存関係チェック
│   │   ├── env.sh           # 環境セットアップ
│   │   ├── execution.sh     # 実行・監視フェーズ
│   │   └── review.sh        # レビューフェーズ
│   ├── log.sh               # ログ出力
│   ├── marker.sh            # マーカー検出ユーティリティ
│   ├── notify.sh            # 通知機能
│   ├── priority.sh          # 優先度計算
│   ├── session-resolver.sh  # セッション名解決ユーティリティ
│   ├── status.sh            # ステータスファイル管理
│   ├── template.sh          # テンプレート処理
│   ├── tracker.sh           # プロンプト効果測定（記録コア）
│   ├── knowledge-loop.sh    # 知識ループコアライブラリ
│   ├── tmux.sh              # tmux操作（後方互換ラッパー）
│   ├── multiplexer.sh       # マルチプレクサ抽象化レイヤー
│   ├── multiplexer-tmux.sh  # tmux実装
│   ├── multiplexer-zellij.sh # Zellij実装
│   ├── workflow.sh          # ワークフローエンジン
│   ├── workflow-finder.sh   # ワークフロー検索
│   ├── workflow-loader.sh   # ワークフロー読み込み
│   ├── workflow-prompt.sh   # プロンプト処理
│   ├── workflow-selector.sh # ワークフロー自動選択（auto モード）
│   ├── worktree.sh          # Git worktree操作
│   └── yaml.sh              # YAMLパーサー
└── scripts/                 # 実行スクリプト
    ├── attach.sh            # セッションアタッチ
    ├── ci-fix-helper.sh     # CI修正ヘルパー（lib/ci-fix.shのラッパー）
    ├── cleanup.sh           # クリーンアップ
    ├── context.sh           # コンテキスト管理
    ├── dashboard.sh         # ダッシュボード表示
    ├── force-complete.sh    # セッション強制完了
    ├── generate-config.sh   # プロジェクト解析・設定生成
    ├── improve.sh           # 継続的改善スクリプト
    ├── knowledge-loop.sh    # 知識ループ（fixコミットから知見抽出・AGENTS.md更新提案）
    ├── init.sh              # プロジェクト初期化
    ├── list.sh              # セッション一覧
    ├── mux-all.sh           # 全セッション表示（マルチプレクサ対応）
    ├── next.sh              # 次のタスク取得
    ├── nudge.sh             # セッションへメッセージ送信
    ├── restart-watcher.sh   # Watcher再起動
    ├── run-batch.sh         # バッチ実行
    ├── run.sh               # タスク起動
    ├── status.sh            # 状態確認
    ├── stop.sh              # セッション停止
    ├── sweep.sh             # 全セッションのマーカーチェック・cleanup
    ├── test.sh              # テスト実行
    ├── tracker.sh           # プロンプト効果測定（集計・表示）
    ├── verify-config-docs.sh # 設定ドキュメントの整合性検証
    ├── wait-for-sessions.sh # 複数セッション完了待機
    └── watch-session.sh     # セッション監視と自動クリーンアップ
```

## 設定

### 設定ファイル形式（YAML）

```yaml
# .pi-runner.yaml

# =====================================
# Worktree設定
# =====================================
worktree:
  base_dir: ".worktrees"     # Worktree作成先
  base_branch: "HEAD"        # ベースブランチ
  copy_files:                # コピーするファイル
    - .env
    - .env.local
    - .envrc

# =====================================
# マルチプレクサ設定
# =====================================
multiplexer:
  type: "tmux"               # マルチプレクサタイプ（tmux または zellij）
  session_prefix: "pi"       # セッション名プレフィックス
  start_in_session: true     # 作成後に自動アタッチ

# =====================================
# piコマンド設定（従来の設定、後方互換性あり）
# =====================================
pi:
  command: "pi"              # piコマンドのパス
  args: ""                   # デフォルト引数

# =====================================
# エージェント設定（複数エージェント対応）
# =====================================
agent:
  type: "pi"                 # エージェントプリセット（pi, claude, opencode, custom）
  # command: "custom-agent"  # カスタムコマンド（type: custom の場合）
  # args: []                 # 追加引数
  # template: '...'          # コマンドテンプレート（type: custom の場合）

# =====================================
# 並列実行設定
# =====================================
parallel:
  max_concurrent: 0          # 最大同時実行数（0 = 無制限）

# =====================================
# ワークフロー設定（デフォルト）
# =====================================
workflow:
  steps:                     # 実行するステップ
    - plan
    - implement
    - review
    - merge

# =====================================
# 名前付きワークフロー設定（複数定義）
# =====================================
workflows:
  # 小規模修正向け
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
  
  # 徹底ワークフロー
  thorough:
    description: 大規模機能開発（複数ファイル、新機能、アーキテクチャ変更）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
  
  # フロントエンド実装向け（context 付き）
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング）
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      ## 技術スタック
      - React / Next.js / TypeScript
      - TailwindCSS
      
      ## 重視すべき点
      - レスポンシブデザイン
      - アクセシビリティ
      - コンポーネントの再利用性

# =====================================
# AI自動選択設定（-w auto 用）
# =====================================
auto:
  provider: "anthropic"       # AIプロバイダー
  model: "claude-haiku-4-5"   # AI自動選択モデル

# =====================================
# 計画書設定
# =====================================
plans:
  keep_recent: 10            # 保持する計画書の数
  dir: "docs/plans"          # 計画書ディレクトリ

# =====================================
# 継続的改善設定
# =====================================
improve:
  review_prompt_file: "agents/improve-review.md"  # カスタムレビュープロンプト
  logs:
    keep_recent: 10          # 保持するログファイル数
    keep_days: 7             # 保持期間（日数）
    dir: ".improve-logs"     # ログディレクトリ

# =====================================
# GitHub統合設定
# =====================================
github:
  include_comments: true     # Issueコメントをプロンプトに含める
  max_comments: 10           # 最大コメント数

# =====================================
# フック設定
# =====================================
hooks:
  allow_inline: false        # インラインフックコマンドを許可
  on_start: ""               # セッション開始時
  on_success: ""             # 成功時
  on_error: ""               # エラー時
  on_cleanup: ""             # クリーンアップ時
  on_improve_start: ""       # improve.sh 開始時
  on_improve_end: ""         # improve.sh 終了時
  on_iteration_start: ""     # 各イテレーション開始時
  on_iteration_end: ""       # 各イテレーション終了時
  on_review_complete: ""     # レビュー完了時

# =====================================
# エージェントテンプレート設定
# =====================================
agents:
  plan: "agents/plan.md"           # 計画ステップ
  implement: "agents/implement.md" # 実装ステップ
  review: "agents/review.md"       # レビューステップ
  merge: "agents/merge.md"         # マージステップ
  test: "agents/test.md"           # テストステップ
  ci-fix: "agents/ci-fix.md"       # CI修正ステップ

# =====================================
# Watcher設定
# =====================================
watcher:
  force_cleanup_on_timeout: false  # PRマージタイムアウト時に強制クリーンアップ
  initial_delay: 10                # 監視開始前の初期遅延（秒）
  cleanup_delay: 5                 # クリーンアップ前の遅延（秒）
  cleanup_retry_interval: 3        # クリーンアップリトライ間隔（秒）
  pr_merge_max_attempts: 10        # PRマージチェック最大試行回数
  pr_merge_retry_interval: 60      # PRマージチェック間隔（秒）

# =====================================
# プロンプトトラッカー設定
# =====================================
tracker:
  file: ".worktrees/.status/tracker.jsonl"  # トラッカーファイルパス
```

### 環境変数による上書き

すべての設定項目は環境変数で上書きできます。

#### Worktree設定

```bash
PI_RUNNER_WORKTREE_BASE_DIR=".worktrees"
PI_RUNNER_WORKTREE_BASE_BRANCH="HEAD"
PI_RUNNER_WORKTREE_COPY_FILES=".env .env.local .envrc"
```

#### マルチプレクサ設定

```bash
PI_RUNNER_MULTIPLEXER_TYPE="tmux"                # tmux または zellij
PI_RUNNER_MULTIPLEXER_SESSION_PREFIX="pi"
PI_RUNNER_MULTIPLEXER_START_IN_SESSION="true"
```

#### エージェント設定

```bash
PI_RUNNER_PI_COMMAND="pi"                        # piコマンドパス（レガシー）
PI_RUNNER_PI_ARGS="--model claude-sonnet-4"      # piコマンド引数（レガシー）
PI_RUNNER_AGENT_TYPE="pi"                        # pi, claude, opencode, custom
PI_RUNNER_AGENT_COMMAND="custom-agent"           # カスタムコマンド
PI_RUNNER_AGENT_ARGS="--verbose"                 # エージェント引数
PI_RUNNER_AGENT_TEMPLATE='{{command}} {{args}}' # カスタムテンプレート
```

#### 並列実行設定

```bash
PI_RUNNER_PARALLEL_MAX_CONCURRENT="5"            # 最大同時実行数
```

#### 計画書設定

```bash
PI_RUNNER_PLANS_KEEP_RECENT="10"                 # 保持する計画書の数
PI_RUNNER_PLANS_DIR="docs/plans"                 # 計画書ディレクトリ
```

#### 継続的改善設定

```bash
PI_RUNNER_IMPROVE_REVIEW_PROMPT_FILE="agents/improve-review.md"
PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT="10"          # 保持するログファイル数
PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS="7"             # 保持期間（日数）
PI_RUNNER_IMPROVE_LOGS_DIR=".improve-logs"       # ログディレクトリ
```

#### GitHub統合設定

```bash
PI_RUNNER_GITHUB_INCLUDE_COMMENTS="true"         # Issueコメントを含める
PI_RUNNER_GITHUB_MAX_COMMENTS="10"               # 最大コメント数
```

#### フック設定

```bash
PI_RUNNER_HOOKS_ALLOW_INLINE="false"             # インラインフック許可
PI_RUNNER_HOOKS_ON_START="./hooks/on-start.sh"
PI_RUNNER_HOOKS_ON_SUCCESS="./hooks/on-success.sh"
PI_RUNNER_HOOKS_ON_ERROR="./hooks/on-error.sh"
PI_RUNNER_HOOKS_ON_CLEANUP="./hooks/on-cleanup.sh"
PI_RUNNER_HOOKS_ON_IMPROVE_START="./hooks/on-improve-start.sh"
PI_RUNNER_HOOKS_ON_IMPROVE_END="./hooks/on-improve-end.sh"
PI_RUNNER_HOOKS_ON_ITERATION_START="./hooks/on-iteration-start.sh"
PI_RUNNER_HOOKS_ON_ITERATION_END="./hooks/on-iteration-end.sh"
PI_RUNNER_HOOKS_ON_REVIEW_COMPLETE="./hooks/on-review-complete.sh"
```

#### エージェントテンプレート設定

```bash
PI_RUNNER_AGENTS_PLAN="agents/plan.md"
PI_RUNNER_AGENTS_IMPLEMENT="agents/implement.md"
PI_RUNNER_AGENTS_REVIEW="agents/review.md"
PI_RUNNER_AGENTS_MERGE="agents/merge.md"
PI_RUNNER_AGENTS_TEST="agents/test.md"
PI_RUNNER_AGENTS_CI_FIX="agents/ci-fix.md"
```

#### AI自動選択設定

```bash
PI_RUNNER_AUTO_PROVIDER="anthropic"              # AIプロバイダー
PI_RUNNER_AUTO_MODEL="claude-haiku-4-5"          # AI自動選択モデル
```

#### Watcher設定

```bash
PI_RUNNER_WATCHER_INITIAL_DELAY="10"             # 初期遅延（秒）
PI_RUNNER_WATCHER_CLEANUP_DELAY="5"              # クリーンアップ前遅延（秒）
PI_RUNNER_WATCHER_CLEANUP_RETRY_INTERVAL="3"     # リトライ間隔（秒）
PI_RUNNER_WATCHER_PR_MERGE_MAX_ATTEMPTS="10"     # PRマージ最大試行回数
PI_RUNNER_WATCHER_PR_MERGE_RETRY_INTERVAL="60"   # PRマージチェック間隔（秒）
PI_RUNNER_WATCHER_FORCE_CLEANUP_ON_TIMEOUT="false" # タイムアウト時強制クリーンアップ
```

#### プロンプトトラッカー設定

```bash
PI_RUNNER_TRACKER_FILE=".worktrees/.status/tracker.jsonl"
```

## CLI コマンド

### run.sh - タスク起動

```bash
./scripts/run.sh <issue-number> [options]

Options:
    -i, --issue NUMBER  Issue番号（位置引数の代替）
    -b, --branch NAME   カスタムブランチ名（デフォルト: issue-<num>-<title>）
    --base BRANCH       ベースブランチ（デフォルト: HEAD）
    -w, --workflow NAME ワークフロー名（デフォルト: default）
                        ビルトイン: default, simple, thorough, ci-fix, auto
    -l, --label LABEL   セッションラベル（識別用タグ）
    --no-attach         セッション作成後にアタッチしない
    --no-cleanup        エージェント終了後の自動クリーンアップを無効化
    --reattach          既存セッションがあればアタッチ
    --force             既存セッション/worktreeを削除して再作成
    --agent-args ARGS   エージェントに渡す追加の引数
    --pi-args ARGS      --agent-args のエイリアス（後方互換性）
    --list-workflows    利用可能なワークフロー一覧を表示
    --ignore-blockers   依存関係チェックをスキップして強制実行
    --show-config       現在の設定を表示（デバッグ用）
    --list-agents       利用可能なエージェントプリセット一覧を表示
    --show-agent-config エージェント設定を表示（デバッグ用）
    -v, --verbose       詳細ログを表示
    --quiet             エラーのみ表示
    -h, --help          このヘルプを表示
```

デフォルトでは、piが終了すると自動的にworktreeとセッションがクリーンアップされます。
`--no-cleanup`を指定すると、クリーンアップをスキップしてworktreeとセッションを保持します。

### list.sh - セッション一覧

```bash
./scripts/list.sh [options]

Options:
    -v, --verbose   詳細情報を表示
    -h, --help      このヘルプを表示
```

### mux-all.sh - 全セッション表示

```bash
./scripts/mux-all.sh [options]

Options:
    -a, --all           全ての *-issue-* セッションを対象
    -p, --prefix NAME   特定のプレフィックスを指定（例: dict）
    -w, --watch         ウォッチモード（tmux: xpanes / zellij: ネイティブペイン）
    -k, --kill          既存のモニターセッションを削除して再作成
    -h, --help          このヘルプを表示

Description:
    全てのpi-issue-runnerセッションを表示します。
    現在のマルチプレクサに応じて最適な表示方法を使用します。

    モード:
        デフォルト          tmux: link-window / zellij: ネイティブペイン
        -w, --watch         tmux: xpanesでタイル表示 / zellij: ネイティブペイン

Examples:
    mux-all.sh -a             # 全セッションを表示
    mux-all.sh -p dict        # dict-issue-* セッションを表示
    mux-all.sh -k             # モニターセッションを再作成
```

### status.sh - 状態確認

```bash
./scripts/status.sh <session-name|issue-number> [options]

Arguments:
    session-name    セッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --output N      セッション出力の最新N行を表示（デフォルト: 20）
    -h, --help      このヘルプを表示
```

### attach.sh - セッションアタッチ

```bash
./scripts/attach.sh <session-name|issue-number>

Arguments:
    session-name    セッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -h, --help      このヘルプを表示

Examples:
    ./scripts/attach.sh pi-issue-42
    ./scripts/attach.sh 42
```

### stop.sh - セッション停止

```bash
./scripts/stop.sh <session-name|issue-number>

Arguments:
    session-name    セッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -h, --help      このヘルプを表示

Examples:
    ./scripts/stop.sh pi-issue-42
    ./scripts/stop.sh 42
```

### sweep.sh - 全セッションのマーカーチェック・cleanup

```bash
./scripts/sweep.sh [options]

Options:
    --dry-run           対象セッションの表示のみ（実行しない）
    --force             cleanup時にPRマージ確認をスキップ
    --check-errors      ERRORマーカーもチェック（デフォルトはCOMPLETEのみ）
    -v, --verbose       詳細ログ出力
    -h, --help          このヘルプを表示

Description:
    全てのアクティブなpi-issue-runnerセッションをスキャンし、
    COMPLETEマーカーが出力されているセッションに対して
    cleanup.shを実行します。
    
    watch-session.shがクラッシュしたりタイミング問題で
    クリーンアップが実行されなかったセッションの検出と
    クリーンアップに使用します。

Examples:
    sweep.sh --dry-run
    sweep.sh --force
    sweep.sh --check-errors
```

### cleanup.sh - クリーンアップ

```bash
./scripts/cleanup.sh <session-name|issue-number> [options]

Options:
    --force, -f       強制削除（未コミットの変更があっても削除）
    --delete-branch   対応するGitブランチも削除
    --keep-session    セッションを維持（worktreeのみ削除）
    --keep-worktree   worktreeを維持（セッションのみ削除）
    --orphans         孤立したステータスファイルをクリーンアップ
    --orphan-worktrees  complete状態だがworktreeが残存しているケースをクリーンアップ
    --delete-plans    クローズ済みIssueの計画書を削除
    --rotate-plans    古い計画書を削除（直近N件を保持、設定: plans.keep_recent）
    --improve-logs    .improve-logsディレクトリをクリーンアップ
    --all             全てのクリーンアップを実行（--orphans + --rotate-plans + --orphan-worktrees + --improve-logs）
    --age <days>      指定日数より古いステータスファイルを削除（--orphansと併用）
    --dry-run         削除せずに対象を表示（--orphans/--delete-plans/--rotate-plans/--allと使用）
    -h, --help        このヘルプを表示
```

### ci-fix-helper.sh - CI修正ヘルパー

```bash
./scripts/ci-fix-helper.sh <command> [arguments]

Commands:
    detect <pr_number>
        CI失敗タイプを検出して出力
        Returns: failure_type (lint|format|test|build|unknown)

    fix <failure_type> [worktree_path]
        指定された失敗タイプの自動修正を試行
        Returns: 0=成功, 1=失敗, 2=AI修正が必要

    handle <issue_number> <pr_number> [worktree_path]
        CI失敗の完全な処理フロー
        - 失敗検出
        - 自動修正試行
        - 変更のコミット＆プッシュ
        Returns: 0=修正成功, 1=エスカレーション必要

    validate [worktree_path]
        ローカル検証を実行（clippy + test）
        Returns: 0=成功, 1=失敗

    escalate <pr_number> <failure_log>
        PRをDraft化してエスカレーション
        Returns: 0=成功, 1=失敗

Examples:
    # CI失敗タイプを検出
    ./scripts/ci-fix-helper.sh detect 123

    # フォーマット修正を試行
    ./scripts/ci-fix-helper.sh fix format /path/to/worktree

    # 完全な処理フロー
    ./scripts/ci-fix-helper.sh handle 42 123 /path/to/worktree

    # ローカル検証
    ./scripts/ci-fix-helper.sh validate /path/to/worktree
```

### context.sh - コンテキスト管理

```bash
./scripts/context.sh <subcommand> [options]

Subcommands:
    show <issue>          Issue固有のコンテキストを表示
    show-project          プロジェクトコンテキストを表示
    add <issue> <text>    Issue固有のコンテキストに追記
    add-project <text>    プロジェクトコンテキストに追記
    edit <issue>          エディタでIssue固有コンテキストを編集
    edit-project          エディタでプロジェクトコンテキストを編集
    list                  コンテキストがあるIssue一覧
    clean [--days N]      古いコンテキストを削除（デフォルト: 30日）
    export <issue>        Markdown形式でエクスポート
    remove <issue>        Issue固有のコンテキストを削除
    remove-project        プロジェクトコンテキストを削除
    init <issue> [title]  Issue固有のコンテキストを初期化
    init-project          プロジェクトコンテキストを初期化

Options:
    -h, --help            このヘルプを表示

Examples:
    # コンテキストを表示
    context.sh show 42
    context.sh show-project

    # コンテキストに追記
    context.sh add 42 "JWT認証は依存ライブラリの問題で失敗"
    context.sh add-project "ShellCheck SC2155を修正する際は変数宣言と代入を分離"

    # エディタで編集
    context.sh edit 42
    context.sh edit-project

    # 一覧表示
    context.sh list

    # クリーンアップ
    context.sh clean --days 30

    # コンテキストを削除
    context.sh remove 42
    context.sh remove-project

    # コンテキストを初期化
    context.sh init 42 "My Feature"
    context.sh init-project
```

### dashboard.sh - ダッシュボード表示

```bash
./scripts/dashboard.sh [options]

Options:
    --json              JSON形式で出力
    --no-color          色なし出力（CI環境向け）
    --compact           コンパクト表示（サマリーのみ）
    --section <name>    特定セクションのみ表示
                        (summary|progress|blocked|ready)
    -w, --watch         自動更新モード（5秒ごと）
    -v, --verbose       詳細情報を表示
    -h, --help          このヘルプを表示

Examples:
    dashboard.sh                    # 標準表示
    dashboard.sh --compact          # サマリーのみ
    dashboard.sh --json             # JSON出力
    dashboard.sh --watch            # 自動更新
    dashboard.sh --section summary  # サマリーのみ表示

Sections:
    summary     サマリー統計
    progress    進行中のIssue
    blocked     ブロックされたIssue
    ready       実行可能なIssue
```

### watch-session.sh - セッション監視と自動クリーンアップ

```bash
./scripts/watch-session.sh <session-name> [options]

Arguments:
    session-name    監視するセッション名

Options:
    --marker <text>       完了マーカー（デフォルト: ###TASK_COMPLETE_<issue>###）
    --interval <sec>      監視間隔（デフォルト: 2秒）
    --cleanup-args        cleanup.shに渡す追加引数
    --no-auto-attach      エラー検知時にTerminalを自動で開かない
    -h, --help            このヘルプを表示
```

#### 動作概要

1. マルチプレクサセッションの出力を定期的にキャプチャ
2. 完了マーカー（`###TASK_COMPLETE_<issue_number>###`）を検出
3. マーカー検出時に `cleanup.sh` を自動実行
4. セッションが終了した場合は監視を停止

#### 使用例

```bash
# run.shから自動的に起動される（通常は直接呼び出さない）
./scripts/watch-session.sh pi-issue-42

# カスタムマーカーを指定
./scripts/watch-session.sh pi-issue-42 --marker "###DONE###"

# 監視間隔を変更
./scripts/watch-session.sh pi-issue-42 --interval 5
```

※ このスクリプトは通常、`run.sh` がバックグラウンドで自動的に起動します。
直接呼び出す必要はありません。

### restart-watcher.sh - Watcher再起動

```bash
./scripts/restart-watcher.sh <session-name|issue-number>

Arguments:
    session-name    セッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -h, --help      このヘルプを表示

Description:
    指定されたセッションのwatcherプロセスを再起動します。
    既存のwatcherが実行中の場合は停止してから新しいwatcherを起動します。

Examples:
    restart-watcher.sh pi-issue-42
    restart-watcher.sh 42
```

### improve.sh - 継続的改善

```bash
./scripts/improve.sh [options]

Options:
    --max-iterations N   最大イテレーション数（デフォルト: 3）
    --max-issues N       1回あたりの最大Issue数（デフォルト: 5）
    --auto-continue      承認ゲートをスキップ（自動継続）
    --dry-run            レビューのみ実行（Issue作成・実行しない）
    --timeout <sec>      各イテレーションのタイムアウト（デフォルト: 3600）
    --review-only        project-reviewスキルで問題を表示するのみ
    -v, --verbose        詳細ログを表示
    -h, --help           このヘルプを表示
```

#### 動作概要

プロジェクトの継続的改善を自動化します：

1. プロジェクトをレビューして問題を発見
2. 発見した問題からGitHub Issueを作成
3. 各Issueに対してpi-issue-runnerを並列実行
4. すべての実行が完了するまで待機
5. 問題がなくなるか最大回数に達するまで繰り返し

#### 使用例

```bash
./scripts/improve.sh
./scripts/improve.sh --max-iterations 2 --max-issues 3
./scripts/improve.sh --dry-run
./scripts/improve.sh --auto-continue
```

### knowledge-loop.sh - 知識ループ

```bash
./scripts/knowledge-loop.sh [options]

Options:
    --since "PERIOD"     対象期間（デフォルト: "1 week ago"）
                         例: "1 week ago", "3 days ago", "1 month ago"
    --apply              提案をAGENTS.mdに自動適用
    --dry-run            提案のみ表示（デフォルト）
    --json               JSON形式で出力
    -h, --help           このヘルプを表示
```

#### 動作概要

fixコミットと`docs/decisions/`から知見を自動抽出し、AGENTS.mdの「既知の制約」セクションへの追加を提案します。

**解析対象**:
1. `fix:` コミット（git log --grep="^fix:"）
2. 新しい `docs/decisions/*.md` ファイル
3. tracker.jsonl の失敗パターン（存在する場合）

#### 使用例

```bash
./scripts/knowledge-loop.sh                         # 直近7日間を解析
./scripts/knowledge-loop.sh --since "1 week ago"    # 同上
./scripts/knowledge-loop.sh --since "3 days ago"    # 直近3日間のみ
./scripts/knowledge-loop.sh --apply                 # AGENTS.mdに自動適用
./scripts/knowledge-loop.sh --dry-run               # プレビューのみ（デフォルト）
```

### nudge.sh - セッションへメッセージ送信

```bash
./scripts/nudge.sh <session-name|issue-number> [options]

Arguments:
    session-name    セッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -m, --message TEXT  送信するメッセージ（デフォルト: "続けてください"）
    -s, --session NAME  セッション名を明示的に指定
    -h, --help          このヘルプを表示
```

#### 使用例

```bash
./scripts/nudge.sh 42
./scripts/nudge.sh pi-issue-42
./scripts/nudge.sh 42 --message "続きをお願いします"
./scripts/nudge.sh --session pi-issue-42 --message "完了しましたか？"
```

### next.sh - 次のタスク取得

```bash
./scripts/next.sh [options]

Options:
    -n, --count <N>     提案するIssue数（デフォルト: 1）
    -l, --label <name>  特定ラベルでフィルタ
    --json              JSON形式で出力
    --dry-run           提案のみ（実行コマンドを表示しない）
    -v, --verbose       詳細な判断理由を表示
    -h, --help          このヘルプを表示

Description:
    次に実行すべきGitHub Issueをインテリジェントに提案します。
    依存関係・優先度・ブロッカー状況を考慮して最適なIssueを選択します。

Prioritization Logic:
    1. Blocker status    - OPENなブロッカーがないIssueを優先
    2. Dependency depth  - 依存が少ない（レイヤーが浅い）Issueを優先
    3. Priority labels   - priority:high > medium > low
    4. Issue number      - 同スコアなら番号が小さい方を優先

Examples:
    next.sh                    # 次の1件を提案
    next.sh -n 3               # 次の3件を提案
    next.sh -l feature         # featureラベル付きから提案
    next.sh --json             # JSON形式で出力
    next.sh -v                 # 詳細な判断理由を表示

Exit codes:
    0 - Success
    1 - No candidates found
    2 - GitHub API error
    3 - Invalid arguments
```

### run-batch.sh - バッチ実行

```bash
./scripts/run-batch.sh <issue-number>... [options]

Arguments:
    issue-number...   実行するIssue番号（複数指定可）

Options:
    --dry-run           実行計画のみ表示（実行しない）
    --sequential        並列実行せず順次実行
    --continue-on-error エラーがあっても次のレイヤーを実行
    --timeout <sec>     完了待機のタイムアウト（デフォルト: 3600）
    --interval <sec>    完了確認の間隔（デフォルト: 5）
    --parent <issue>    親IssueのSubtaskを自動展開（将来拡張）
    --workflow <name>   使用するワークフロー名（デフォルト: default）
    --base <branch>     ベースブランチ（デフォルト: HEAD）
    -q, --quiet         進捗表示を抑制
    -v, --verbose       詳細ログを出力
    -h, --help          このヘルプを表示
```

#### 動作概要

複数のGitHub Issueを依存関係順に並列実行します：

1. 各IssueのSubtaskから依存関係を解析
2. 依存関係に基づいてレイヤーを計算
3. 各レイヤーのIssueを並列実行
4. すべてのIssueが完了するまで待機

#### 使用例

```bash
./scripts/run-batch.sh 482 483 484 485 486
./scripts/run-batch.sh 482 483 --dry-run
./scripts/run-batch.sh 482 483 --sequential
./scripts/run-batch.sh 482 483 --continue-on-error
```

#### 終了コード

| コード | 意味 |
|--------|------|
| 0 | 全Issue成功 |
| 1 | 一部Issueが失敗 |
| 2 | 循環依存を検出 |
| 3 | 引数エラー |

### init.sh - プロジェクト初期化

```bash
./scripts/init.sh [options]

Options:
    --full          完全セットアップ（agents/, workflows/ も作成）
    --minimal       最小セットアップ（.pi-runner.yaml のみ）
    --force         既存ファイルを上書き
    -h, --help      このヘルプを表示
```

#### 使用例

```bash
./scripts/init.sh              # 標準セットアップ
./scripts/init.sh --full       # 完全セットアップ
./scripts/init.sh --minimal    # 最小セットアップ
./scripts/init.sh --force      # 既存ファイルを上書き
```

### generate-config.sh - プロジェクト解析・設定生成

```bash
./scripts/generate-config.sh [options]

Options:
    -o, --output FILE   出力ファイルパス (default: .pi-runner.yaml)
    --dry-run           ファイルに書き込まず標準出力に表示
    --force             既存ファイルを上書き
    --no-ai             AI生成をスキップし、静的テンプレートのみ使用
    --validate          既存の設定をスキーマで検証
    -h, --help          このヘルプを表示

Description:
    プロジェクトの構造をAIで解析し、最適な .pi-runner.yaml を生成します。
    AI (pi --print) が利用できない場合は静的テンプレートにフォールバックします。

Environment Variables:
    PI_COMMAND                  piコマンドのパス (default: pi)
    PI_RUNNER_AUTO_PROVIDER     AIプロバイダー (default: anthropic)
    PI_RUNNER_AUTO_MODEL        AIモデル (default: claude-haiku-4-5)

Examples:
    generate-config.sh                  # AI解析して .pi-runner.yaml を生成
    generate-config.sh --dry-run        # 結果をプレビュー
    generate-config.sh --no-ai          # 静的テンプレートで生成
    generate-config.sh --validate       # 既存設定を検証
    generate-config.sh -o custom.yaml   # カスタム出力先
```

### force-complete.sh - セッション強制完了（⚠️ 非推奨）

> **⚠️ 非推奨**: `force-complete.sh` は非推奨です。代わりに `stop.sh <target> --cleanup` を使用してください。
> このスクリプトは内部的に `stop.sh --cleanup` にリダイレクトされます。

```bash
./scripts/force-complete.sh <session-name|issue-number> [options]

Arguments:
    session-name    セッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    --error         エラーマーカーを送信
    --message <msg> カスタムメッセージを追加
    -h, --help      このヘルプを表示
```

#### 動作概要

指定されたセッションに完了マーカーを送信し、watch-session.shによる自動クリーンアップをトリガーします。

AIが完了マーカーを出力し忘れた場合や、手動でタスク完了を判断した場合に使用してください。

#### 使用例

```bash
# 推奨: stop.sh --cleanup を直接使用
./scripts/stop.sh 42 --cleanup
./scripts/stop.sh pi-issue-42 --cleanup

# 非推奨（force-complete.sh は stop.sh にリダイレクト）
./scripts/force-complete.sh 42
./scripts/force-complete.sh pi-issue-42
./scripts/force-complete.sh 42 --error
./scripts/force-complete.sh 42 --message "Manual completion"
./scripts/force-complete.sh 42 --error --message "Stopped by user"
```

### test.sh - テスト実行

```bash
./scripts/test.sh [options] [target]

Options:
    -v, --verbose     詳細ログを表示
    -f, --fail-fast   最初の失敗で終了
    -s, --shellcheck  ShellCheckを実行
    -a, --all         全てのチェック（bats + shellcheck）を実行
    -j, --jobs N      並列実行のジョブ数（デフォルト: 4）
    --fast            高速モード（重いテストをスキップ）
    -h, --help        このヘルプを表示
```

#### ターゲット

| ターゲット | 説明 |
|-----------|------|
| `lib` | test/lib/*.bats のみ実行 |
| `scripts` | test/scripts/*.bats のみ実行 |
| `regression` | test/regression/*.bats のみ実行 |
| `skills` | test/skills/**/*.bats のみ実行 |
| (デフォルト) | 全Batsテストを実行 |

#### 使用例

```bash
./scripts/test.sh             # 全Batsテスト実行
./scripts/test.sh lib         # test/lib/*.bats のみ
./scripts/test.sh -v          # 詳細ログ付き
./scripts/test.sh -f          # fail-fast モード
./scripts/test.sh -s          # ShellCheckのみ実行
./scripts/test.sh -a          # Batsテスト + ShellCheck
```

### tracker.sh - プロンプト効果測定

```bash
./scripts/tracker.sh [options]

Options:
    --by-workflow       ワークフロー別成功率を表示
    --failures          失敗パターン分析（直近の失敗一覧）
    --since "N days"    期間指定（N日以内のエントリのみ）
    --json              JSON形式で出力
    -h, --help          このヘルプを表示
```

#### 使用例

```bash
./scripts/tracker.sh                    # 全記録を表示
./scripts/tracker.sh --by-workflow      # ワークフロー別成功率
./scripts/tracker.sh --failures         # 失敗パターン分析
./scripts/tracker.sh --since "7 days"   # 直近7日間のみ
./scripts/tracker.sh --json             # JSON形式で出力
```

### verify-config-docs.sh - 設定ドキュメントの整合性検証

```bash
./scripts/verify-config-docs.sh [options]

Options:
    -v, --verbose  詳細出力を表示
    -h, --help     このヘルプを表示

Description:
    lib/config.sh と docs/configuration.md の整合性を検証します。
    設定項目の定義とドキュメントの記載が一致していることを確認します。

Examples:
    # 検証を実行
    ./scripts/verify-config-docs.sh

    # 詳細出力付き
    ./scripts/verify-config-docs.sh --verbose

Exit codes:
    0  All checks passed
    1  Configuration mismatch detected
```

### wait-for-sessions.sh - 複数セッション完了待機

```bash
./scripts/wait-for-sessions.sh <issue-number>... [options]

Arguments:
    issue-number...   待機するIssue番号（複数指定可）

Options:
    --timeout <sec>   タイムアウト秒数（デフォルト: 3600 = 1時間）
    --interval <sec>  チェック間隔（デフォルト: 5秒）
    --fail-fast       1つでもエラーになったら即座に終了
    --quiet           進捗表示を抑制
    -h, --help        このヘルプを表示
```

#### 動作概要

指定したIssue番号のセッションがすべて完了するまで待機します。
ステータスファイル（`.worktrees/.status/<issue>.json`）を監視し、
全セッションが完了したら正常終了します。

#### 使用例

```bash
./scripts/wait-for-sessions.sh 140 141 144
./scripts/wait-for-sessions.sh 140 141 --timeout 1800
./scripts/wait-for-sessions.sh 140 141 --fail-fast
```

#### 終了コード

| コード | 意味 |
|--------|------|
| 0 | 全セッションが正常完了 |
| 1 | 1つ以上のセッションがエラー |
| 2 | タイムアウト |
| 3 | 引数エラー |

## 依存関係

### 必須

- **Bash** 4.3以上
- **Git** 2.17以上（worktreeサポート）
- **GitHub CLI** 2.0以上（認証済み）
- **tmux** 2.1以上 または **Zellij** 0.32以上
- **jq** 1.6以上（JSON処理）
- **pi** latest

### オプション

- **yq** (YAMLパーサー、ワークフローカスタマイズに必要)

## 非機能要件

### 信頼性

- 必須コマンドの存在確認（jq, gh等）
- エラー発生時の適切なメッセージ表示
- Worktree/セッションの孤立を防ぐクリーンアップ

### 互換性

- macOS / Linux対応
- Bash 4.3+互換

### セキュリティ

- `.env`ファイルのコピー時の権限保持
- GitHub認証情報の安全な取り扱い

## 制約事項

### 技術的制約

- 同一Issue番号で複数のworktreeは作成不可
- マルチプレクサセッション名の一意性が必要
- Git worktreeの制限に従う（サブモジュール等）

### 運用制約

- Worktree削除前にマルチプレクサセッションを終了する必要がある
- GitHub CLI認証が必須
- プロジェクトルートからの実行を推奨

## 将来の拡張（Phase 2）

以下の機能は将来のバージョンで検討予定です：

### 状態管理

- タスクの状態追跡（queued, running, completed, failed）
- 実行時間の記録
- 終了コードの保存
- 永続化されたタスク情報（JSON形式）

### ログ管理

- 各タスクのログをファイルに保存
- リアルタイムログストリーミング
- ログの検索・フィルタリング

### その他

- Docker/Podman統合
- GitHub Actions連携強化
- PR自動作成
- 依存関係解決の高度化
- Webhookサポート

## 将来の拡張（Phase 3）

- WebダッシュボードUI
- メトリクス収集・可視化
- 複数リポジトリ対応
- チーム機能（タスク共有）

## 参考資料

- [orchestrator-hybrid](https://github.com/takemo101/orchestrator-hybrid)
- [pi-mono](https://github.com/badlogic/pi-mono)
- [Git worktree documentation](https://git-scm.com/docs/git-worktree)
- [tmux documentation](https://github.com/tmux/tmux/wiki)
- [Zellij documentation](https://zellij.dev/documentation/)
