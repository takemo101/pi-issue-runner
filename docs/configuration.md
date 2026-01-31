# 設定

## 概要

Pi Issue Runnerの動作は設定ファイルでカスタマイズできます。設定ファイルはプロジェクトルートに配置します。

## 設定ファイルの場所

設定ファイルは以下の順序で検索され、最初に見つかったものが使用されます：

1. プロジェクトルート: `./.pi-runner.yaml`
2. 親ディレクトリを再帰的に検索
3. デフォルト設定（ファイルなし）

> **Note**: 現在、コマンドラインオプションで設定ファイルを指定する機能は未実装です。

## 設定フォーマット

### YAML形式

```yaml
# .pi-runner.yaml

# Git Worktree設定
worktree:
  base_dir: ".worktrees"        # Worktreeの作成先ディレクトリ
  copy_files:                   # Worktreeに自動コピーするファイル
    - ".env"
    - ".env.local"
    - ".envrc"

# Tmux設定
tmux:
  session_prefix: "pi"          # セッション名のプレフィックス
  start_in_session: true        # 作成後に自動アタッチ

# Pi設定
pi:
  command: "pi"                 # piコマンドのパス
  args:                         # デフォルトで渡す引数
    - "--verbose"

# 並列実行設定
parallel:
  max_concurrent: 5             # 最大同時実行数（0=無制限）
```

## 設定項目の詳細

### worktree

#### base_dir
- **型**: `string`
- **デフォルト**: `.worktrees`
- **説明**: Git worktreeを作成するディレクトリ

#### copy_files
- **型**: `string[]`
- **デフォルト**: `.env .env.local .envrc`
- **説明**: Worktree作成時にコピーするファイルのリスト（プロジェクトルートからの相対パス）

### tmux

#### session_prefix
- **型**: `string`
- **デフォルト**: `pi`
- **説明**: Tmuxセッション名のプレフィックス（実際のセッション名: `{prefix}-{issue番号}`）

#### start_in_session
- **型**: `boolean`
- **デフォルト**: `true`
- **説明**: タスク作成後、自動的にセッションにアタッチ

### pi

#### command
- **型**: `string`
- **デフォルト**: `pi`
- **説明**: piコマンドのパス（フルパスまたはPATH内のコマンド名）

#### args
- **型**: `string[]`
- **デフォルト**: `[]`（空）
- **説明**: piコマンドに常に渡す追加引数

**例**:
```yaml
pi:
  args:
    - "--verbose"
    - "--model"
    - "claude-sonnet-4"
```

### parallel

#### max_concurrent
- **型**: `number`
- **デフォルト**: `0`（無制限）
- **説明**: 同時に実行できるタスクの最大数

**推奨値**: CPUコア数の50-75%

## 環境変数

設定ファイルの代わりに、またはオーバーライドとして環境変数を使用できます：

| 環境変数 | 説明 | 例 |
|---------|------|-----|
| `PI_RUNNER_WORKTREE_BASE_DIR` | Worktreeのベースディレクトリ | `.worktrees` |
| `PI_RUNNER_WORKTREE_COPY_FILES` | コピーするファイル（スペース区切り） | `.env .env.local` |
| `PI_RUNNER_TMUX_SESSION_PREFIX` | Tmuxセッションプレフィックス | `pi` |
| `PI_RUNNER_TMUX_START_IN_SESSION` | 自動アタッチ | `true` |
| `PI_RUNNER_PI_COMMAND` | piコマンドのパス | `pi` |
| `PI_RUNNER_PI_ARGS` | piコマンドの引数（スペース区切り） | `--verbose` |
| `PI_RUNNER_PARALLEL_MAX_CONCURRENT` | 最大同時実行数 | `5` |
| `LOG_LEVEL` | ログレベル（DEBUG, INFO, WARN, ERROR, QUIET） | `DEBUG` |

## ログレベル

`LOG_LEVEL` 環境変数でログの出力レベルを制御できます。

### 利用可能なログレベル

| レベル | 説明 |
|--------|------|
| `DEBUG` | デバッグ情報を含む全てのログを表示 |
| `INFO` | 一般的な情報ログを表示（デフォルト） |
| `WARN` | 警告とエラーのみ表示 |
| `ERROR` | エラーのみ表示 |
| `QUIET` | ログを出力しない |

ログレベルの優先順位: `DEBUG` < `INFO` < `WARN` < `ERROR` < `QUIET`

### 使用例

```bash
# デバッグログを表示（トラブルシューティング時）
LOG_LEVEL=DEBUG ./scripts/run.sh 42

# エラーのみ表示（静かに実行）
LOG_LEVEL=ERROR ./scripts/run.sh 42

# ログを完全に抑制
LOG_LEVEL=QUIET ./scripts/run.sh 42
```

### 関連する関数

`lib/log.sh` で以下の関数が利用可能です：

```bash
# ログレベルを設定
set_log_level "DEBUG"

# DEBUGモードを有効化
enable_verbose

# QUIETモードを有効化（エラーのみ表示）
enable_quiet
```

## 設定の優先順位

1. **環境変数** (最優先)
2. **設定ファイル**
3. **デフォルト値** (最低優先)

## 設定例

### 開発環境

```yaml
# .pi-runner.yaml (開発)
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env.local"
    - ".envrc"

tmux:
  start_in_session: true

pi:
  args:
    - "--verbose"

parallel:
  max_concurrent: 3
```

### 本番環境（CI/CD）

```yaml
# .pi-runner.yaml (本番)
worktree:
  base_dir: "/tmp/pi-worktrees"
  copy_files:
    - ".env.production"

tmux:
  start_in_session: false  # 非対話モード

parallel:
  max_concurrent: 10
```

### チーム開発

```yaml
# .pi-runner.yaml (チーム)
worktree:
  base_dir: ".worktrees"
  copy_files:
    - ".env.local"
    - ".npmrc"

parallel:
  max_concurrent: 5
```

## 設定のベストプラクティス

1. **環境ごとに設定ファイルを分ける**: 開発/本番で異なる設定を使用
2. **機密情報は環境変数で**: `.env`ファイル等は設定ファイルに含めずコピー対象として指定
3. **リソース制限を適切に設定**: マシンスペックに応じて`max_concurrent`を調整
4. **設定のバージョン管理**: `.pi-runner.yaml`はGitで管理

## 設定の実装詳細

設定は `lib/config.sh` でBashスクリプトとして実装されています。

### 主要な関数

```bash
# 設定ファイルを探す
find_config_file [start_dir]

# 設定を読み込む
load_config [config_file]

# 設定値を取得
get_config <key>

# 設定を再読み込み（テスト用）
reload_config [config_file]

# 設定を表示（デバッグ用）
show_config
```

### 使用例

```bash
source lib/config.sh

# 設定を読み込む
load_config

# 設定値を取得
base_dir=$(get_config worktree_base_dir)
echo "Worktree directory: $base_dir"

# デバッグ: 全設定を表示
show_config
```

## トラブルシューティング

### 設定ファイルが読み込まれない

```bash
# 設定ファイルの場所を確認
find .pi-runner.yaml

# 設定内容を確認（lib/config.shのshow_config関数を使用）
source lib/config.sh
load_config
show_config
```

### デフォルト設定に戻す

```bash
# 設定ファイルを削除
rm .pi-runner.yaml
```

## 将来の拡張予定

以下の機能は将来のバージョンで実装予定です：

- `--config` オプションによる設定ファイル指定
- `tmux.log_output`: セッション出力のファイル記録
- `pi.timeout`: タスクのタイムアウト設定
- `parallel.queue_strategy`: キュー戦略（fifo/priority）
- `parallel.auto_cleanup`: 完了後の自動クリーンアップ
- `github`: GitHub API設定
- `logging`: ログ設定
- `notifications`: 通知設定（Slack等）
- `error`: エラーハンドリング設定
- `resources`: リソース制限設定
- JSON形式の設定ファイルサポート
