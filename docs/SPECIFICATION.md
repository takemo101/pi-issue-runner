# Pi Issue Runner - 仕様書

## 概要

Pi Issue RunnerはGitHub Issueを入力として、Git worktreeとtmuxセッションを活用して複数のpiインスタンスを並列実行するタスクランナーです。

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

### 3. Tmuxセッション統合

- 各タスクを独立したtmuxセッション内で実行
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

- Worktreeの削除
- tmuxセッションの終了
- ブランチの削除（`--delete-branch`オプション）

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
Tmuxセッションを作成（tmux new-session）
    ↓
.pi-prompt.mdを生成（Issue情報を埋め込み）
    ↓
セッション内でpiを起動（pi @.pi-prompt.md）
    ↓
完了後、オプションでクリーンアップ
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
├── .pi-runner.yml           # ユーザー設定
├── lib/                     # シェルスクリプトライブラリ
│   ├── config.sh            # 設定管理
│   ├── github.sh            # GitHub CLI操作
│   ├── log.sh               # ログ出力
│   ├── tmux.sh              # tmux操作
│   └── worktree.sh          # Git worktree操作
└── scripts/                 # 実行スクリプト
    ├── run.sh               # タスク起動
    ├── list.sh              # セッション一覧
    ├── status.sh            # 状態確認
    ├── attach.sh            # セッションアタッチ
    ├── stop.sh              # セッション停止
    └── cleanup.sh           # クリーンアップ
```

## 設定

### 設定ファイル形式（YAML）

```yaml
# .pi-runner.yml
worktree:
  base_dir: ".worktrees"     # Worktree作成先
  copy_files: ".env"         # コピーするファイル（スペース区切り）

tmux:
  session_prefix: "pi"       # セッション名プレフィックス
  start_in_session: true     # 作成後に自動アタッチ

pi:
  command: "pi"              # piコマンドのパス
  args: ""                   # デフォルト引数

parallel:
  max_concurrent: 0          # 最大同時実行数（0 = 無制限）
```

### 環境変数による上書き

```bash
PI_RUNNER_WORKTREE_BASE_DIR=".worktrees"
PI_RUNNER_TMUX_SESSION_PREFIX="pi"
PI_RUNNER_PI_COMMAND="pi"
PI_RUNNER_PARALLEL_MAX_CONCURRENT="5"
```

## CLI コマンド

### run.sh - タスク起動

```bash
./scripts/run.sh <issue-number> [options]

Options:
    --branch NAME   カスタムブランチ名
    --base BRANCH   ベースブランチ（デフォルト: HEAD）
    --no-attach     セッション作成後にアタッチしない
    --reattach      既存セッションがあればアタッチ
    --force         既存セッション/worktreeを削除して再作成
    --pi-args ARGS  piに渡す追加の引数
```

### status.sh - 状態確認

```bash
./scripts/status.sh [options]

Options:
    --all           すべてのセッションを表示
    --json          JSON形式で出力
```

### attach.sh - セッションアタッチ

```bash
./scripts/attach.sh <session-name|issue-number>
```

### stop.sh - セッション停止

```bash
./scripts/stop.sh <session-name|issue-number>

Arguments:
    session-name    tmuxセッション名（例: pi-issue-42）
    issue-number    GitHub Issue番号（例: 42）

Options:
    -h, --help      このヘルプを表示

Examples:
    ./scripts/stop.sh pi-issue-42
    ./scripts/stop.sh 42
```

### cleanup.sh - クリーンアップ

```bash
./scripts/cleanup.sh <session-name|issue-number> [options]

Options:
    --force, -f       強制削除
    --delete-branch   対応するGitブランチも削除
    --keep-session    セッションを維持
    --keep-worktree   worktreeを維持
```

## 依存関係

### 必須

- **Bash** 4.0以上
- **Git** 2.17以上（worktreeサポート）
- **GitHub CLI** 2.0以上（認証済み）
- **tmux** 2.1以上
- **jq** 1.6以上（JSON処理）
- **pi** latest

### オプション

- **yq** (YAML設定ファイルの高度な処理)

## 非機能要件

### 信頼性

- 必須コマンドの存在確認（jq, gh等）
- エラー発生時の適切なメッセージ表示
- Worktree/セッションの孤立を防ぐクリーンアップ

### 互換性

- macOS / Linux対応
- Bash 4.0+互換

### セキュリティ

- `.env`ファイルのコピー時の権限保持
- GitHub認証情報の安全な取り扱い

## 制約事項

### 技術的制約

- 同一Issue番号で複数のworktreeは作成不可
- Tmuxセッション名の一意性が必要
- Git worktreeの制限に従う（サブモジュール等）

### 運用制約

- Worktree削除前にtmuxセッションを終了する必要がある
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

- Zellij対応（tmux代替）
- Docker/Podman統合
- GitHub Actions連携
- PR自動作成
- 依存関係解決（Issue間の依存）
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
