# 設定ファイルリファレンス

Pi Issue Runnerは `.pi-runner.yaml` ファイルで設定をカスタマイズできます。

## 設定ファイルの場所

プロジェクトルートに `.pi-runner.yaml` を配置します。

```
my-project/
├── .pi-runner.yaml    # 設定ファイル
├── src/
└── ...
```

## 完全な設定例

```yaml
# .pi-runner.yaml

# =====================================
# Worktree設定
# =====================================
worktree:
  # worktreeの作成先ディレクトリ
  # デフォルト: .worktrees
  base_dir: .worktrees
  
  # worktree作成時にコピーするファイル
  # デフォルト: .env .env.local .envrc
  copy_files:
    - .env
    - .env.local
    - .envrc
    - config/database.yml    # 例: Railsプロジェクトの場合
    - config/secrets.yml     # 例: Railsプロジェクトの場合

# =====================================
# tmux設定
# =====================================
# マルチプレクサ設定
# =====================================
multiplexer:
  # 使用するマルチプレクサ
  # tmux または zellij
  # デフォルト: tmux
  type: tmux
  
  # セッション名のプレフィックス
  # 実際のセッション名: {prefix}-issue-{number}
  # デフォルト: pi
  session_prefix: pi
  
  # セッション内で起動するか
  # デフォルト: true
  start_in_session: true

# =====================================
# piコマンド設定（従来の設定、後方互換性あり）
# =====================================
pi:
  # piコマンドのパス
  # デフォルト: pi
  command: pi
  
  # piに渡す追加引数
  # デフォルト: (なし)
  args:
    - --model
    - claude-sonnet-4-20250514

# =====================================
# エージェント設定（複数エージェント対応）
# =====================================
agent:
  # エージェントプリセット: pi, claude, opencode, custom
  # デフォルト: pi（agent未設定時はpi.commandを使用）
  type: pi
  
  # カスタムコマンド（type: customの場合に使用）
  # command: my-agent
  
  # 追加引数
  # args:
  #   - --verbose
  
  # カスタムテンプレート（type: customの場合に使用）
  # template: '{{command}} {{args}} --file "{{prompt_file}}"'

# =====================================
# 並列実行設定
# =====================================
parallel:
  # 同時実行数の上限
  # 0 = 無制限
  # デフォルト: 0
  max_concurrent: 3

# =====================================
# ワークフロー設定（デフォルト）
# =====================================
# 注: -w オプション未指定時に使用されるデフォルトワークフロー
#     ワークフロー名を指定する場合は workflows/*.yaml を作成し、-w オプションを使用
workflow:
  # 実行するステップ
  # ビルトイン: plan, implement, review, merge
  # カスタムステップも定義可能（対応するエージェントテンプレートが必要）
  steps:
    - plan
    - implement
    - review
    - merge

# =====================================
# 計画書設定
# =====================================
plans:
  # 保持する計画書の件数（0 = 全て保持）
  # デフォルト: 10
  keep_recent: 10
  
  # 計画書ディレクトリ
  # デフォルト: docs/plans
  dir: "docs/plans"

# =====================================
# improve-logs クリーンアップ設定
# =====================================
improve_logs:
  # 保持するログファイルの件数（0 = 全て保持）
  # デフォルト: 10
  keep_recent: 10
  
  # 保持するログファイルの日数（0 = 日数制限なし）
  # デフォルト: 7
  keep_days: 7
  
  # ログファイルの保存ディレクトリ
  # デフォルト: .improve-logs
  dir: ".improve-logs"

# =====================================
# エージェント設定（オプション）
# =====================================
agents:
  # 各ステップのエージェントテンプレートファイル
  plan: agents/plan.md
  implement: agents/implement.md
  review: agents/review.md
  merge: agents/merge.md
  test: agents/test.md
  ci-fix: agents/ci-fix.md
```

## 設定項目詳細

### worktree

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `base_dir` | string | `.worktrees` | worktreeの作成先ディレクトリ |
| `copy_files` | string[] | `.env .env.local .envrc` | worktree作成時にコピーするファイル |

#### copy_filesの使い方

環境固有の設定ファイル（.env等）はGit管理外のため、worktree作成時にコピーが必要です。

```yaml
worktree:
  copy_files:
    - .env                    # 環境変数
    - .env.local              # ローカル環境変数
    - config/master.key       # Railsマスターキー
    - .npmrc                  # npm認証情報
```

### multiplexer

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `type` | string | `tmux` | 使用するマルチプレクサ（`tmux` または `zellij`） |
| `session_prefix` | string | `pi` | セッション名のプレフィックス |
| `start_in_session` | boolean | `true` | セッション内で起動するか |

#### セッション名の形式

```
{session_prefix}-issue-{issue_number}
```

例: `pi-issue-42`

#### Zellijを使用する場合

```yaml
multiplexer:
  type: zellij
  session_prefix: my-project
```

環境変数でも切り替え可能:
```bash
PI_RUNNER_MULTIPLEXER_TYPE=zellij pi-run 42
PI_RUNNER_MULTIPLEXER_SESSION_PREFIX=my-project pi-run 42
```

### pi

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `command` | string | `pi` | piコマンドのパス |
| `args` | string[] | (なし) | piに渡す追加引数 |

#### argsの使い方

```yaml
pi:
  command: /usr/local/bin/pi
  args:
    - --model
    - claude-sonnet-4-20250514
    - --dangerously-skip-permissions
```

### agent

> **新機能**: 複数のコーディングエージェントに対応しました。

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `type` | string | (なし) | エージェントプリセット（pi, claude, opencode, custom） |
| `command` | string | (プリセットによる) | エージェントコマンドのパス |
| `args` | string[] | (なし) | エージェントに渡す追加引数 |
| `template` | string | (プリセットによる) | コマンド生成テンプレート |

#### サポートされるプリセット

| プリセット | コマンド | 説明 |
|-----------|---------|------|
| `pi` | `pi @"prompt.md"` | Pi coding agent（デフォルト） |
| `claude` | `claude --print "prompt.md"` | Claude Code |
| `opencode` | `cat prompt.md \| opencode` | OpenCode (stdin経由) |
| `custom` | (テンプレートによる) | カスタムエージェント |

#### 使用例

```yaml
# Claude Codeを使用
agent:
  type: claude

# OpenCodeを使用
agent:
  type: opencode

# カスタムエージェントを使用
agent:
  type: custom
  command: my-agent
  template: '{{command}} {{args}} --file "{{prompt_file}}"'
```

#### テンプレート変数

カスタムテンプレートで使用可能な変数については、[テンプレート変数リファレンス](#テンプレート変数リファレンス)を参照してください。

エージェントコマンドテンプレートでは以下の変数が使用できます：
- `{{command}}` - エージェントコマンド
- `{{args}}` - 引数（agent.args + --agent-args）
- `{{prompt_file}}` - プロンプトファイルのパス

#### 後方互換性

`agent` セクションが未設定の場合、`pi` セクションの設定が使用されます。
既存の設定はそのまま動作します。

```yaml
# 従来の設定（引き続き動作）
pi:
  command: pi
  args:
    - --model
    - claude-sonnet-4-20250514
```

### parallel

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `max_concurrent` | integer | `0` | 同時実行数の上限（0=無制限） |

#### 並列実行の制御

```yaml
# CPUコア数に合わせて制限
parallel:
  max_concurrent: 4

# 無制限（デフォルト）
parallel:
  max_concurrent: 0
```

### plans

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `keep_recent` | integer | `10` | 保持する計画書の件数（0 = 全て保持） |
| `dir` | string | `docs/plans` | 計画書の保存先ディレクトリ |

#### 計画書のローテーション

計画書は自動的にローテーションされ、古い計画書が削除されます。

```yaml
# 最新20件の計画書のみ保持
plans:
  keep_recent: 20
  dir: "docs/plans"

# 全ての計画書を保持（自動削除無効）
plans:
  keep_recent: 0
```

#### 計画書の保存場所

計画書は `{dir}/issue-{number}-plan.md` という命名規則で保存されます。

```
docs/plans/
├── issue-42-plan.md
├── issue-43-plan.md
└── issue-44-plan.md
```

### improve_logs

`.improve-logs` ディレクトリの自動クリーンアップ設定

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `keep_recent` | integer | `10` | 直近何件のログを保持するか（0 = 全て保持） |
| `keep_days` | integer | `7` | 何日以内のログを保持するか（0 = 日数制限なし） |
| `dir` | string | `.improve-logs` | ログファイルの保存ディレクトリ |

#### ログファイルのクリーンアップ

`improve.sh` が生成するログファイルは、設定に基づいて自動的にクリーンアップできます。

```yaml
# 最新10件かつ7日以内のログを保持
improve_logs:
  keep_recent: 10
  keep_days: 7
  dir: .improve-logs

# 全てのログを保持（自動削除無効）
improve_logs:
  keep_recent: 0
  keep_days: 0
```

#### 使用方法

```bash
# 設定に従ってクリーンアップ
./scripts/cleanup.sh --improve-logs

# 特定の日数で上書き（7日以上前のログを削除）
./scripts/cleanup.sh --improve-logs --age 7

# ドライラン（削除せずに対象を表示）
./scripts/cleanup.sh --improve-logs --dry-run

# 全てのクリーンアップ（improve-logsも含む）
./scripts/cleanup.sh --all
```

#### 削除条件

ログファイルは以下の条件で削除されます：

- **keep_recent**: 更新日時の新しい順に並べて、N件を超えるファイルを削除
- **keep_days**: N日より古いファイルを削除
- 両方が設定されている場合、いずれかの条件に該当すると削除

**例**: `keep_recent: 10, keep_days: 7` の場合
- 最新10件のログは保持（日時にかかわらず）
- 11件目以降のログは、7日以内なら保持、7日より古ければ削除

### workflow

**重要**: `.pi-runner.yaml` の `workflow` セクションは、**`-w` オプションを指定しない場合に使用される「デフォルトワークフロー」**を定義します。

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `steps` | string[] | `plan implement review merge` | 実行するステップ |

> **注意**: `workflow.name` は `.pi-runner.yaml` では無視されます（後方互換性のために残されています）。ワークフロー名を指定する場合は `-w` オプションと `workflows/*.yaml` を使用してください。

#### ビルトインステップ

| ステップ | 説明 |
|---------|------|
| `plan` | 実装計画を作成 |
| `implement` | コードを実装 |
| `review` | コードレビュー |
| `merge` | PRを作成してマージ |
| `test` | テストを実行 |
| `ci-fix` | CI失敗を修正 |

#### デフォルトワークフローのカスタマイズ例

```yaml
# .pi-runner.yaml
# この設定は `./scripts/run.sh 42` （-w オプションなし）で使用される
workflow:
  steps:
    - plan
    - implement
    - review
    - merge

# 簡易ワークフローに変更する場合
workflow:
  steps:
    - implement
    - merge
```

**ワークフロー名を指定して実行する場合**:
```bash
# workflows/simple.yaml を使用
./scripts/run.sh 42 -w simple
```

詳細なワークフローの使い分けについては [ワークフロードキュメント](./workflows.md) を参照してください。

### github

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `include_comments` | boolean | `true` | Issueコメントをプロンプトに含めるか |
| `max_comments` | integer | `10` | 取り込むコメントの最大数（0 = 無制限） |

#### 使用例

```yaml
github:
  include_comments: true  # Issueコメントを含める
  max_comments: 10        # 最新10件のコメントのみ
```

### agents

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `{step}` | string | (ビルトイン) | ステップのエージェントテンプレートファイル |

#### エージェントテンプレートの作成

```markdown
<!-- agents/plan.md -->
# Plan Agent

GitHub Issue #{{issue_number}} の実装計画を作成します。

## コンテキスト
- **Issue**: #{{issue_number}} - {{issue_title}}
- **ブランチ**: {{branch_name}}
- **Worktree**: {{worktree_path}}

## タスク
1. Issue内容を分析
2. 実装方針を決定
3. 作業項目をリスト化
```

#### テンプレート変数

エージェントテンプレートで使用可能な変数については、[テンプレート変数リファレンス](#テンプレート変数リファレンス)を参照してください。

## テンプレート変数リファレンス

Pi Issue Runnerでは、2つの異なるコンテキストでテンプレート変数が使用されます。

### エージェントコマンドテンプレート（`agent.template`）

カスタムエージェント（`agent.type: custom`）のコマンド生成に使用されます。

| 変数 | 説明 | 例 |
|------|------|-----|
| `{{command}}` | エージェントコマンド | `my-agent` |
| `{{args}}` | 引数（agent.args + --agent-args） | `--verbose --timeout 60` |
| `{{prompt_file}}` | プロンプトファイルのパス | `/tmp/prompt-plan.md` |

**使用例**:
```yaml
agent:
  type: custom
  command: my-agent
  template: '{{command}} {{args}} --file "{{prompt_file}}"'
```

### エージェントプロンプトテンプレート（`agents/*.md`）

エージェントテンプレートファイル（Markdown）内で使用されます。

| 変数 | 説明 | 例 |
|------|------|-----|
| `{{issue_number}}` | GitHub Issue番号 | `411` |
| `{{issue_title}}` | Issueタイトル | `docs: テンプレート変数一覧の統合` |
| `{{branch_name}}` | ブランチ名 | `issue-411-docs` |
| `{{worktree_path}}` | worktreeのパス | `.worktrees/issue-411` |
| `{{step_name}}` | 現在のステップ名 | `plan`, `implement` |
| `{{workflow_name}}` | ワークフロー名 | `default`, `simple` |
| `{{plans_dir}}` | 計画書ディレクトリパス | `docs/plans` |
| `{{pr_number}}` | PR番号 | `123` |

**使用例**:
```markdown
<!-- agents/plan.md -->
# Plan Agent

GitHub Issue #{{issue_number}} の実装計画を作成します。

## コンテキスト
- **Issue**: #{{issue_number}} - {{issue_title}}
- **ブランチ**: {{branch_name}}
- **Worktree**: {{worktree_path}}
```

### 実装との整合性

テンプレート変数の実装は `lib/template.sh` の `render_template()` 関数で定義されています。新しい変数を追加する場合は、この関数も更新する必要があります。

## 環境変数による上書き

すべての設定は環境変数で上書き可能です。

| 環境変数 | 設定項目 |
|---------|---------|
| `PI_RUNNER_WORKTREE_BASE_DIR` | `worktree.base_dir` |
| `PI_RUNNER_WORKTREE_COPY_FILES` | `worktree.copy_files` |
| `PI_RUNNER_MULTIPLEXER_TYPE` | `multiplexer.type` |
| `PI_RUNNER_MULTIPLEXER_SESSION_PREFIX` | `multiplexer.session_prefix` |
| `PI_RUNNER_MULTIPLEXER_START_IN_SESSION` | `multiplexer.start_in_session` |
| `PI_RUNNER_PI_COMMAND` | `pi.command` |
| `PI_RUNNER_PI_ARGS` | `pi.args` |
| `PI_RUNNER_AGENT_TYPE` | `agent.type` |
| `PI_RUNNER_AGENT_COMMAND` | `agent.command` |
| `PI_RUNNER_AGENT_ARGS` | `agent.args` |
| `PI_RUNNER_AGENT_TEMPLATE` | `agent.template` |
| `PI_RUNNER_AGENTS_PLAN` | `agents.plan` |
| `PI_RUNNER_AGENTS_IMPLEMENT` | `agents.implement` |
| `PI_RUNNER_AGENTS_REVIEW` | `agents.review` |
| `PI_RUNNER_AGENTS_MERGE` | `agents.merge` |
| `PI_RUNNER_AGENTS_TEST` | `agents.test` |
| `PI_RUNNER_AGENTS_CI_FIX` | `agents.ci-fix` |
| `PI_RUNNER_PARALLEL_MAX_CONCURRENT` | `parallel.max_concurrent` |
| `PI_RUNNER_PLANS_KEEP_RECENT` | `plans.keep_recent` |
| `PI_RUNNER_PLANS_DIR` | `plans.dir` |
| `PI_RUNNER_GITHUB_INCLUDE_COMMENTS` | `github.include_comments` |
| `PI_RUNNER_GITHUB_MAX_COMMENTS` | `github.max_comments` |
| `PI_RUNNER_IMPROVE_LOGS_KEEP_RECENT` | `improve_logs.keep_recent` |
| `PI_RUNNER_IMPROVE_LOGS_KEEP_DAYS` | `improve_logs.keep_days` |
| `PI_RUNNER_IMPROVE_LOGS_DIR` | `improve_logs.dir` |

### 例: CI環境での使用

```bash
export PI_RUNNER_PI_COMMAND="/opt/pi/bin/pi"
export PI_RUNNER_PARALLEL_MAX_CONCURRENT=2
./scripts/run.sh 42
```

### 例: Claude Codeを使用

```bash
export PI_RUNNER_AGENT_TYPE="claude"
./scripts/run.sh 42
```

### 例: カスタムエージェントテンプレートを使用

```bash
export PI_RUNNER_AGENTS_PLAN="custom/plan.md"
export PI_RUNNER_AGENTS_IMPLEMENT="custom/implement.md"
./scripts/run.sh 42
```

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

## 設定の優先順位

1. **環境変数** (最優先)
2. **設定ファイル**
3. **デフォルト値** (最低優先)

## 設定ファイルの検索順序

1. カレントディレクトリの `.pi-runner.yaml`
2. 親ディレクトリを順に検索
3. 見つからない場合はデフォルト値を使用

## ワークフローファイルの検索順序

ワークフローの検索順序は、`-w` オプションの有無によって異なります。

### `-w` オプション未指定時（デフォルトワークフロー）

```bash
./scripts/run.sh 42
```

1. `.pi-runner.yaml` の `workflow` セクション（推奨）
2. `.pi/workflow.yaml`
3. `workflows/default.yaml`
4. ビルトイン `default`

### `-w` オプション指定時（名前付きワークフロー）

```bash
./scripts/run.sh 42 -w simple
```

1. `.pi/workflow.yaml`
2. `workflows/{name}.yaml`（上記例では `workflows/simple.yaml`）
3. ビルトイン `{name}`（上記例では `simple`）

> **重要**: `-w` オプションを指定した場合、`.pi-runner.yaml` の `workflow` セクションは**無視**されます。これは、明示的なワークフロー指定が設定ファイルのデフォルトより優先されるためです。

### 使い分けの指針

| 方法 | 使用シナリオ |
|------|-------------|
| `.pi-runner.yaml` の `workflow` セクション | プロジェクト全体のデフォルトワークフローを定義。通常はこれを使用。 |
| `workflows/*.yaml` | 複数のワークフローを切り替えて使用する場合。`-w` オプションで選択。 |
| `.pi/workflow.yaml` | プロジェクト固有のワークフローを単一ファイルで管理する場合（どちらの方法でも使用可能）。 |

## エージェントファイルの検索順序

1. `agents/{step}.md`
2. `.pi/agents/{step}.md`
3. ビルトインプロンプト

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

# デフォルトワークフロー（-w オプション未指定時に使用）
workflow:
  steps:
    - plan
    - implement
    - review
    - merge
```

## 設定の実装詳細

設定は複数のモジュールで処理されます:

### 基本設定: lib/config.sh

以下の設定は `lib/config.sh` で処理されます:
- `worktree.*` - worktreeのベースディレクトリ、コピーするファイル
- `tmux.*` - セッション名のプレフィックス、セッション内起動設定
- `pi.*` - piコマンドのパス、追加引数（後方互換性）
- `agent.*` - エージェントプリセット、カスタムコマンド、引数、テンプレート
- `parallel.*` - 並列実行の最大同時実行数
- `plans.*` - 計画書の保持数、ディレクトリ
- `github.*` - Issueコメントの取り込み設定

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

### ワークフロー設定: lib/workflow-loader.sh

以下の設定は `lib/workflow-loader.sh` で処理されます:
- `.pi-runner.yaml` 内の `workflow.steps` - 実行するステップの定義
- `workflows/*.yaml` ファイル - カスタムワークフロー定義ファイル

ワークフロー設定の詳細は [ワークフロードキュメント](workflows.md) を参照してください。

## トラブルシューティング

### 設定が反映されない

```bash
# デバッグモードで確認
DEBUG=1 ./scripts/run.sh 42

# または show_config で確認
source lib/config.sh
load_config
show_config
```

### 設定ファイルが読み込まれない

```bash
# 設定ファイルの場所を確認
find .pi-runner.yaml

# 設定内容を確認（lib/config.shのshow_config関数を使用）
source lib/config.sh
load_config
show_config
```

### yqがインストールされていない

workflow設定でyqが必要です。インストール:

```bash
# macOS
brew install yq

# Ubuntu
sudo snap install yq
```

yqがない場合はビルトインワークフローにフォールバックします。

### デフォルト設定に戻す

```bash
# 設定ファイルを削除
rm .pi-runner.yaml
```

## メンテナンス

### ドキュメントと実装の整合性検証

`lib/config.sh` の設定項目と `docs/configuration.md` の整合性を自動的に検証できます。

```bash
# 整合性チェック
./scripts/verify-config-docs.sh

# 詳細出力
./scripts/verify-config-docs.sh --verbose
```

**検証内容**:
- `lib/config.sh` で定義された全ての `CONFIG_*` 変数がドキュメントに記載されているか
- デフォルト値が正確に記載されているか（サンプル抽出）
- 主要なセクションが存在するか

**終了コード**:
- `0`: 全チェック成功
- `1`: 不整合検出

**CIでの使用**: このスクリプトをCI/CDパイプラインに組み込むことで、設定項目の追加時にドキュメントの更新漏れを防止できます。

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
