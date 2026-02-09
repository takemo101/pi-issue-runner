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
│   ├── ci-monitor.sh        # CI状態監視
│   ├── ci-retry.sh          # CI自動修正リトライ管理
│   ├── cleanup-improve-logs.sh # 改善ログのクリーンアップ
│   ├── cleanup-orphans.sh   # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh     # 計画書のローテーション
│   ├── config.sh            # 設定管理
│   ├── daemon.sh            # プロセスデーモン化
│   ├── dependency.sh        # 依存関係解析・レイヤー計算
│   ├── github.sh            # GitHub CLI操作
│   ├── hooks.sh             # Hook機能
│   ├── log.sh               # ログ出力
│   ├── notify.sh            # 通知機能
│   ├── status.sh            # ステータスファイル管理
│   ├── template.sh          # テンプレート処理
│   ├── tmux.sh              # tmux操作（後方互換ラッパー）
│   ├── multiplexer.sh       # マルチプレクサ抽象化レイヤー
│   ├── multiplexer-tmux.sh  # tmux実装
│   ├── multiplexer-zellij.sh # Zellij実装
│   ├── workflow.sh          # ワークフローエンジン
│   ├── workflow-finder.sh   # ワークフロー検索
│   ├── workflow-loader.sh   # ワークフロー読み込み
│   ├── workflow-prompt.sh   # プロンプト処理
│   ├── worktree.sh          # Git worktree操作
│   └── yaml.sh              # YAMLパーサー
└── scripts/                 # 実行スクリプト
    ├── attach.sh            # セッションアタッチ
    ├── cleanup.sh           # クリーンアップ
    ├── force-complete.sh    # セッション強制完了
    ├── improve.sh           # 継続的改善スクリプト
    ├── init.sh              # プロジェクト初期化
    ├── list.sh              # セッション一覧
    ├── nudge.sh             # セッションへメッセージ送信
    ├── run-batch.sh         # バッチ実行
    ├── run.sh               # タスク起動
    ├── status.sh            # 状態確認
    ├── stop.sh              # セッション停止
    ├── test.sh              # テスト実行
    ├── wait-for-sessions.sh # 複数セッション完了待機
    └── watch-session.sh     # セッション監視と自動クリーンアップ
```

## 設定

### 設定ファイル形式（YAML）

```yaml
# .pi-runner.yaml
worktree:
  base_dir: ".worktrees"     # Worktree作成先
  copy_files: ".env"         # コピーするファイル（スペース区切り）

multiplexer:
  type: "tmux"               # マルチプレクサタイプ（tmux または zellij）
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
PI_RUNNER_MULTIPLEXER_TYPE="tmux"
PI_RUNNER_MULTIPLEXER_SESSION_PREFIX="pi"
PI_RUNNER_PI_COMMAND="pi"
PI_RUNNER_PARALLEL_MAX_CONCURRENT="5"
```

## CLI コマンド

### run.sh - タスク起動

```bash
./scripts/run.sh <issue-number> [options]

Options:
    --branch NAME     カスタムブランチ名
    --base BRANCH     ベースブランチ（デフォルト: HEAD）
    --workflow NAME   ワークフロー名（デフォルト: default）
                      ビルトイン: default, simple, thorough, ci-fix, auto
    --no-attach       セッション作成後にアタッチしない
    --no-cleanup      pi終了後の自動クリーンアップを無効化
    --reattach        既存セッションがあればアタッチ
    --force           既存セッション/worktreeを削除して再作成
    --agent-args ARGS エージェントに渡す追加の引数
    --pi-args ARGS    --agent-args のエイリアス（後方互換性）
    --list-workflows  利用可能なワークフロー一覧を表示
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

### cleanup.sh - クリーンアップ

```bash
./scripts/cleanup.sh <session-name|issue-number> [options]

Options:
    --force, -f       強制削除
    --delete-branch   対応するGitブランチも削除
    --keep-session    セッションを維持
    --keep-worktree   worktreeを維持
```

### watch-session.sh - セッション監視と自動クリーンアップ

```bash
./scripts/watch-session.sh <session-name> [options]

Arguments:
    session-name    監視するセッション名

Options:
    --marker <text>   完了マーカー（デフォルト: ###TASK_COMPLETE_<issue>###）
    --interval <sec>  監視間隔（デフォルト: 2秒）
    --cleanup-args    cleanup.shに渡す追加引数
    -h, --help        このヘルプを表示
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

### force-complete.sh - セッション強制完了

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
    -j, --jobs N      並列実行のジョブ数（デフォルト: 16）
    --fast            高速モード（重いテストをスキップ）
    -h, --help        このヘルプを表示
```

#### ターゲット

| ターゲット | 説明 |
|-----------|------|
| `lib` | test/lib/*.bats のみ実行 |
| `scripts` | test/scripts/*.bats のみ実行 |
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

- **Bash** 4.0以上
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
- Bash 4.0+互換

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
