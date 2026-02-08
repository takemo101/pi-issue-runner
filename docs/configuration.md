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
  
  # デフォルトのベースブランチ
  # --base オプションで上書き可能
  # デフォルト: HEAD
  base_branch: origin/develop
  
  # worktree作成時にコピーするファイル
  # デフォルト: .env .env.local .envrc
  copy_files:
    - .env
    - .env.local
    - .envrc
    - config/database.yml    # 例: Railsプロジェクトの場合
    - config/secrets.yml     # 例: Railsプロジェクトの場合

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
# 名前付きワークフロー設定（複数定義）
# =====================================
# 注: -w NAME オプションで選択、または -w auto で AI が自動選択
workflows:
  # 小規模バグ修正向け
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
  
  # 大規模機能開発向け
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
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
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
      - アクセシビリティ (WCAG 2.1 AA)
      - コンポーネントの再利用性
      - パフォーマンス（Core Web Vitals）
  
  # バックエンド実装向け（context 付き）
  backend:
    description: バックエンドAPI実装（DB操作、認証、ビジネスロジック、サーバーサイド処理）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    context: |
      ## 技術スタック
      - Node.js / Express / TypeScript
      - PostgreSQL / Prisma
      
      ## 重視すべき点
      - RESTful API設計
      - 入力バリデーション
      - エラーハンドリングとログ
      - ユニットテスト・統合テストの充実
  
  # 設計ドキュメント作成向け（カスタムステップ）
  design:
    description: 設計ドキュメント作成（技術調査、アーキテクチャ設計、ADR、仕様書）
    steps:
      - research  # カスタムステップ（agents/research.md が必要）
      - design    # カスタムステップ（agents/design.md が必要）
      - review
      - merge
    context: |
      ## 目的
      このワークフローはコード実装ではなく、設計ドキュメントの作成に特化する。
      
      ## 成果物
      - docs/ 以下に Markdown ドキュメントを作成
      - コードの変更は原則行わない
      
      ## 重視すべき点
      - 背景・課題・代替案の明記
      - 図やテーブルを使った可視化
      - 将来の拡張性への言及
      - 既存コード・ドキュメントとの整合性
  
  # ワークフロー固有のエージェント設定（agent オーバーライド）
  quick-haiku:
    description: 小規模修正（高速・低コスト）
    steps:
      - implement
      - merge
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5  # 軽量モデル
  
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

# =====================================
# auto ワークフロー選択設定
# =====================================
# `-w auto` で AI が workflows から自動選択する際の設定
auto:
  # AIプロバイダー
  # デフォルト: agent設定から推定 or anthropic
  provider: anthropic
  
  # AIモデル（軽量・高速なモデル推奨）
  # デフォルト: claude-haiku-4-5
  model: claude-haiku-4-5

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
# Watcher設定
# =====================================
watcher:
  # セッション監視の初期遅延（秒）
  # プロンプトが表示されるまで待機する時間
  # デフォルト: 10
  initial_delay: 10
  
  # cleanup実行前の待機時間（秒）
  # セッション終了後、worktree削除前に待機する
  # デフォルト: 5
  cleanup_delay: 5
  
  # cleanupリトライ間隔（秒）
  # cleanup失敗時のリトライ間隔
  # デフォルト: 3
  cleanup_retry_interval: 3
  
  # PRマージチェックの最大試行回数
  # 完了マーカー検出後、PRがマージされるまで待機する回数
  # デフォルト: 10
  pr_merge_max_attempts: 10
  
  # PRマージチェック間隔（秒）
  # 各チェック間の待機時間
  # デフォルト: 60
  pr_merge_retry_interval: 60

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
| `base_branch` | string | `HEAD` | worktree作成時のデフォルトベースブランチ（`--base`オプションで上書き可能） |
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

#### ワークフローごとのagent設定

> **新機能**: ワークフローごとに異なるエージェントを使用できます。

ワークフロー定義内で `agent` プロパティを指定すると、そのワークフローを実行する際にグローバルなagent設定をオーバーライドできます。

| キー | 型 | 説明 |
|------|------|------|
| `workflows.<name>.agent.type` | string | エージェントプリセット（pi, claude, opencode, custom） |
| `workflows.<name>.agent.command` | string | カスタムエージェントコマンド |
| `workflows.<name>.agent.args` | string[] | 追加引数 |
| `workflows.<name>.agent.template` | string | コマンドテンプレート |

**使用例**:

```yaml
# グローバルなエージェント設定
agent:
  type: pi
  args:
    - --model
    - claude-sonnet-4

# ワークフローごとのagent設定
workflows:
  # 小規模修正: 高速・低コストモデル
  quick:
    description: 小規模修正（typo、設定変更等）
    steps: [implement, merge]
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5  # 軽量モデルでコスト削減
  
  # 徹底レビュー: 最高精度モデル
  thorough:
    description: 大規模機能開発
    steps: [plan, implement, test, review, merge]
    agent:
      type: claude
      args:
        - --model
        - claude-opus-4  # 最高精度でバグを削減
  
  # カスタムエージェント
  experimental:
    description: 実験的機能開発
    steps: [implement, review, merge]
    agent:
      type: custom
      command: my-experimental-agent
      template: '{{command}} {{args}} --input "{{prompt_file}}"'
```

**使い方**:

```bash
# quick ワークフローを実行（claude-haiku-4-5を使用）
./scripts/run.sh 42 -w quick

# thorough ワークフローを実行（claude-opus-4を使用）
./scripts/run.sh 42 -w thorough

# agent未指定のワークフローはグローバル設定を使用
./scripts/run.sh 42 -w simple  # グローバルのagent設定を使用
```

**設定の優先順位**:

1. ワークフロー固有の `workflows.<name>.agent` 設定
2. グローバルな `agent` 設定
3. 従来の `pi` 設定（後方互換性）

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

### watcher

セッション監視（`watch-session.sh`）の動作設定

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `initial_delay` | integer | `10` | セッション監視開始前の初期遅延（秒） |
| `cleanup_delay` | integer | `5` | cleanup実行前の待機時間（秒） |
| `cleanup_retry_interval` | integer | `3` | cleanupリトライ間隔（秒） |
| `pr_merge_max_attempts` | integer | `10` | PRマージチェックの最大試行回数 |
| `pr_merge_retry_interval` | integer | `60` | PRマージチェックのリトライ間隔（秒） |

#### タイミング調整の指針

これらの設定値は環境やユースケースに応じて調整できます：

**高速環境（ローカル開発）**:
```yaml
watcher:
  initial_delay: 5           # 高速起動時は短縮可能
  cleanup_delay: 3           # プロセス終了が早い
  pr_merge_max_attempts: 5   # 高速ネットワークでは少なめでOK
```

**低速環境（CI、高負荷サーバー）**:
```yaml
watcher:
  initial_delay: 15          # プロンプト表示に時間がかかる場合
  cleanup_delay: 10          # プロセス終了に余裕を持たせる
  pr_merge_max_attempts: 20  # ネットワーク遅延を考慮
  pr_merge_retry_interval: 120  # チェック間隔を長めに
```

**タイムアウトの計算**:
PR merge チェックのタイムアウト時間は以下の式で計算されます：
```
タイムアウト = pr_merge_max_attempts × pr_merge_retry_interval
```

デフォルト: `10 × 60 = 600秒（10分）`

#### 使用例

```yaml
# .pi-runner.yaml
watcher:
  # 高速環境向けの設定
  initial_delay: 5
  cleanup_delay: 3
  cleanup_retry_interval: 2
  pr_merge_max_attempts: 10
  pr_merge_retry_interval: 60
```

環境変数でも設定可能：
```bash
# 初期遅延を15秒に変更
PI_RUNNER_WATCHER_INITIAL_DELAY=15 ./scripts/run.sh 42

# PRマージチェックを20分に延長
PI_RUNNER_WATCHER_PR_MERGE_MAX_ATTEMPTS=20 \
PI_RUNNER_WATCHER_PR_MERGE_RETRY_INTERVAL=60 \
./scripts/run.sh 42
```

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

> **注意**: `workflow.name` は `.pi-runner.yaml` では無視されます（後方互換性のために残されています）。ワークフロー名を指定する場合は `-w` オプションと `workflows` セクションまたは `workflows/*.yaml` を使用してください。

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

# .pi-runner.yaml の workflows.quick を使用
./scripts/run.sh 42 -w quick

# AI が自動選択
./scripts/run.sh 42 -w auto
```

詳細なワークフローの使い分けについては [ワークフロードキュメント](./workflows.md) を参照してください。

### workflows

> **新機能**: 複数の名前付きワークフローを `.pi-runner.yaml` 内で定義できます。

`.pi-runner.yaml` の `workflows` セクションで複数の名前付きワークフローを定義できます。`-w NAME` で明示的に選択するか、`-w auto` で AI が自動選択します。

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `{name}.description` | string | (なし) | ワークフローの説明（`--list-workflows` と `-w auto` で使用） |
| `{name}.steps` | string[] | (必須) | 実行するステップ |
| `{name}.context` | string | (なし) | ワークフロー固有のコンテキスト（全ステップに注入） |

#### 基本的な使い方

```yaml
# .pi-runner.yaml
workflows:
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
  
  thorough:
    description: 大規模機能開発（複数ファイル、新機能、アーキテクチャ変更）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
```

**実行**:
```bash
# quick ワークフローを使用
./scripts/run.sh 42 -w quick

# thorough ワークフローを使用
./scripts/run.sh 42 -w thorough

# 利用可能なワークフロー一覧
./scripts/run.sh --list-workflows
```

#### description フィールド

`description` は2つの用途で使用されます：

1. **`--list-workflows`**: ユーザーがワークフローを選ぶときの参考情報
2. **`-w auto`**: AI が Issue 内容と照合して最適なワークフローを選択する際の判断基準

> **ベストプラクティス**: `description` を具体的に書くほど AI の自動選択精度が向上します。曖昧な description は誤選択の原因になるため、対象となるタスクの特徴を明確に記載してください。

#### context フィールド

`context` フィールドに記述した内容は、ワークフローの全ステップのプロンプトに「Workflow Context」セクションとして注入されます。技術スタック、重視すべき点、注意事項などを記述します。

```yaml
# .pi-runner.yaml
workflows:
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
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
      - アクセシビリティ (WCAG 2.1 AA)
      - コンポーネントの再利用性
      - パフォーマンス（Core Web Vitals）
  
  backend:
    description: バックエンドAPI実装（DB操作、認証、ビジネスロジック、サーバーサイド処理）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    context: |
      ## 技術スタック
      - Node.js / Express / TypeScript
      - PostgreSQL / Prisma
      
      ## 重視すべき点
      - RESTful API設計
      - 入力バリデーション
      - エラーハンドリングとログ
      - ユニットテスト・統合テストの充実
```

プロンプトへの注入イメージ：

```markdown
## Workflow: frontend

### Workflow Context

## 技術スタック
- React / Next.js / TypeScript
- TailwindCSS

## 重視すべき点
- レスポンシブデザイン
- アクセシビリティ (WCAG 2.1 AA)
...

---

### Step 1: Plan
...
```

#### カスタムステップの使用

ビルトインステップ（`plan`, `implement`, `test`, `review`, `merge`, `ci-fix`）以外に、任意のカスタムステップを定義できます。カスタムステップを使う場合は、対応するエージェントテンプレートを `agents/{step}.md` に配置する必要があります。

```yaml
# .pi-runner.yaml
workflows:
  design:
    description: 設計ドキュメント作成（技術調査、アーキテクチャ設計、ADR、仕様書）
    steps:
      - research  # カスタムステップ
      - design    # カスタムステップ
      - review
      - merge
    context: |
      ## 目的
      このワークフローはコード実装ではなく、設計ドキュメントの作成に特化する。
      
      ## 成果物
      - docs/ 以下に Markdown ドキュメントを作成
      - コードの変更は原則行わない
```

対応するエージェントテンプレート（`agents/research.md`）を作成：

```markdown
# agents/research.md
GitHub Issue #{{issue_number}} に関する技術調査を行います。

## コンテキスト
- **Issue**: #{{issue_number}} {{issue_title}}
- **ブランチ**: {{branch_name}}

## タスク
1. Issue の要件を分析し、解決すべき課題を明確化
2. 関連する既存コード・ドキュメントを調査
3. 外部の技術ドキュメント・ベストプラクティスを確認
4. 技術的な選択肢と制約を洗い出す
5. 調査結果を docs/ 以下にメモとしてまとめる

## 注意
- この段階ではコードの実装は行わない
- 調査結果は次の design ステップで使用される
```

> **エージェントテンプレートの検索順序**: `agents/{step}.md` → `.pi/agents/{step}.md` → ビルトインフォールバック。カスタムステップのテンプレートが見つからない場合はビルトインの `implement` プロンプトがフォールバックとして使用されます。

#### -w auto: AI によるワークフロー自動選択

`-w auto` を指定すると（`workflows` セクション定義時は省略でも自動適用）、AI が Issue の内容を分析して最適なワークフローを事前選択し、そのワークフローのステップ（`agents/*.md`）が展開されたプロンプトを生成します。

```bash
# AI が Issue #42 の内容を見てワークフローを自動選択
./scripts/run.sh 42 -w auto

# workflows セクションがあれば省略可
./scripts/run.sh 42
```

**選択の流れ（2段階処理）:**

1. **事前選択**: `pi --print` + 軽量モデル（haiku）で、Issue の `title` / `body` と各ワークフローの `description` を照合して最適なワークフロー名を判定
2. **プロンプト生成**: 選択されたワークフローで通常の `generate_workflow_prompt()` を実行し、`agents/*.md` の具体的なステップ指示が展開されたプロンプトを生成

**フォールバック:**

AI呼び出しが失敗した場合は、Issue タイトルのプレフィックス（`feat:` → feature, `fix:` → fix, `docs:` → docs 等）によるルールベース判定、さらに失敗した場合は `default` にフォールバックします。

**設定（`.pi-runner.yaml`）:**

```yaml
auto:
  provider: anthropic                # AIプロバイダー（省略時: agent設定から推定 or anthropic）
  model: claude-haiku-4-5   # 軽量モデル推奨（省略時: claude-haiku-4-5）
```

> **ベストプラクティス**: AI が正確に選択できるよう、`description` には対象となるタスクの特徴（規模、領域、技術スタックなど）を具体的に記述してください。

#### ワークフロー名の重複

`.pi-runner.yaml` の `workflows` セクションでビルトインワークフローと同名のワークフロー（例: `ci-fix`）を定義した場合、**`.pi-runner.yaml` の定義が優先されます**。`--list-workflows` では重複を排除し、プロジェクト定義を優先表示します。

```yaml
# .pi-runner.yaml
workflows:
  # ビルトインの ci-fix をオーバーライド
  ci-fix:
    description: カスタムCI修正ワークフロー（プロジェクト固有のルール適用）
    steps:
      - ci-fix
    context: |
      ## プロジェクト固有のCI設定
      - pre-commit hooks を使用
      - 特定のlinterルールをスキップしない
```

#### workflow vs workflows の関係

| セクション | 用途 | `-w` オプション |
|-----------|------|---------------|
| `workflow` | デフォルトワークフロー | 未指定時に使用 |
| `workflows` | 名前付きワークフロー | `-w NAME` または `-w auto` で選択 |

両方を定義することで、デフォルトのワークフローを持ちつつ、状況に応じて別のワークフローを選択できます。

```yaml
# .pi-runner.yaml
# デフォルト（-w オプションなし）
workflow:
  steps:
    - plan
    - implement
    - review
    - merge

# 名前付きワークフロー（-w オプションで選択）
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
      - merge
  
  frontend:
    description: フロントエンド実装
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      技術スタック: React / Next.js
```

使用例：
```bash
./scripts/run.sh 42          # workflow セクションを使用
./scripts/run.sh 42 -w quick # workflows.quick を使用
./scripts/run.sh 42 -w auto  # AI が workflows から選択
```

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

### hooks

#### セッションライフサイクル

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `on_start` | string | (なし) | セッション開始時に実行するスクリプトまたはコマンド |
| `on_success` | string | (なし) | セッション成功時に実行するスクリプトまたはコマンド |
| `on_error` | string | (なし) | セッションエラー時に実行するスクリプトまたはコマンド |
| `on_cleanup` | string | (なし) | クリーンアップ時に実行するスクリプトまたはコマンド |

#### 継続的改善（improve.sh）ライフサイクル

| キー | 型 | デフォルト | 説明 |
|------|------|-----------|------|
| `on_improve_start` | string | (なし) | improve.sh 全体の開始時に実行するスクリプトまたはコマンド |
| `on_improve_end` | string | (なし) | improve.sh 全体の終了時に実行するスクリプトまたはコマンド |
| `on_iteration_start` | string | (なし) | 各イテレーション開始時に実行するスクリプトまたはコマンド |
| `on_iteration_end` | string | (なし) | 各イテレーション完了時に実行するスクリプトまたはコマンド |
| `on_review_complete` | string | (なし) | レビュー完了・Issue作成前に実行するスクリプトまたはコマンド |

#### 使用例

```yaml
hooks:
  # セッションライフサイクル
  # 例: ./hooks/notify-start.sh (ユーザーが作成)
  on_start: ./hooks/notify-start.sh
  on_success: echo "Task completed for Issue #$PI_ISSUE_NUMBER"
  on_error: |
    curl -X POST https://example.com/webhook \
      -H 'Content-Type: application/json' \
      -d "{\"issue\": \"$PI_ISSUE_NUMBER\", \"error\": \"$PI_ERROR_MESSAGE\"}"
  # 例: ./hooks/cleanup-resources.sh (ユーザーが作成)
  on_cleanup: ./hooks/cleanup-resources.sh
  
  # 継続的改善（improve.sh）ライフサイクル
  on_improve_start: |
    echo "🔄 Improve started: iteration $PI_ITERATION/$PI_MAX_ITERATIONS"
  on_review_complete: |
    echo "📋 Review found $PI_REVIEW_ISSUES_COUNT issues"
  on_iteration_end: |
    echo "✅ Iteration $PI_ITERATION: $PI_ISSUES_SUCCEEDED succeeded, $PI_ISSUES_FAILED failed"
  on_improve_end: |
    osascript -e 'display notification "改善完了: $PI_ISSUES_SUCCEEDED/$PI_ISSUES_CREATED 成功" with title "Pi Runner"'
```

#### 環境変数

hookスクリプトには以下の環境変数が渡されます：

**セッション関連**:

| 環境変数 | 説明 | 利用可能イベント |
|----------|------|-----------------|
| `PI_ISSUE_NUMBER` | Issue番号 | on_start, on_success, on_error, on_cleanup |
| `PI_ISSUE_TITLE` | Issueタイトル | on_start, on_success, on_error, on_cleanup |
| `PI_SESSION_NAME` | セッション名 | on_start, on_success, on_error, on_cleanup |
| `PI_BRANCH_NAME` | ブランチ名 | on_start, on_success, on_error, on_cleanup |
| `PI_WORKTREE_PATH` | worktreeパス | on_start, on_success, on_error, on_cleanup |
| `PI_ERROR_MESSAGE` | エラーメッセージ | on_error |
| `PI_EXIT_CODE` | 終了コード | on_error, on_cleanup |

**継続的改善（improve.sh）関連**:

| 環境変数 | 説明 | 利用可能イベント |
|----------|------|-----------------|
| `PI_ITERATION` | 現在のイテレーション番号 | on_iteration_start, on_iteration_end, on_review_complete |
| `PI_MAX_ITERATIONS` | 最大イテレーション数 | on_improve_start, on_improve_end, on_iteration_start, on_iteration_end, on_review_complete |
| `PI_ISSUES_CREATED` | 作成されたIssue数 | on_iteration_end, on_improve_end |
| `PI_ISSUES_SUCCEEDED` | 成功したIssue数 | on_iteration_end, on_improve_end |
| `PI_ISSUES_FAILED` | 失敗したIssue数 | on_iteration_end, on_improve_end |
| `PI_REVIEW_ISSUES_COUNT` | レビューで発見された問題数 | on_review_complete |

> **⚠️ 非推奨**: テンプレート変数（`{{issue_number}}`等）はセキュリティ上の理由により非推奨です。
> 環境変数を使用してください。詳細は [Hook機能ドキュメント](./hooks.md#マイグレーションガイド) を参照してください。

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
| `PI_RUNNER_WORKTREE_BASE_BRANCH` | `worktree.base_branch` |
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
| `PI_RUNNER_HOOKS_ON_START` | `hooks.on_start` |
| `PI_RUNNER_HOOKS_ON_SUCCESS` | `hooks.on_success` |
| `PI_RUNNER_HOOKS_ON_ERROR` | `hooks.on_error` |
| `PI_RUNNER_HOOKS_ON_CLEANUP` | `hooks.on_cleanup` |
| `PI_RUNNER_HOOKS_ON_IMPROVE_START` | `hooks.on_improve_start` |
| `PI_RUNNER_HOOKS_ON_IMPROVE_END` | `hooks.on_improve_end` |
| `PI_RUNNER_HOOKS_ON_ITERATION_START` | `hooks.on_iteration_start` |
| `PI_RUNNER_HOOKS_ON_ITERATION_END` | `hooks.on_iteration_end` |
| `PI_RUNNER_HOOKS_ON_REVIEW_COMPLETE` | `hooks.on_review_complete` |
| `PI_RUNNER_AUTO_PROVIDER` | `auto.provider` |
| `PI_RUNNER_AUTO_MODEL` | `auto.model` |
| `PI_RUNNER_WATCHER_INITIAL_DELAY` | `watcher.initial_delay` |
| `PI_RUNNER_WATCHER_CLEANUP_DELAY` | `watcher.cleanup_delay` |
| `PI_RUNNER_WATCHER_CLEANUP_RETRY_INTERVAL` | `watcher.cleanup_retry_interval` |
| `PI_RUNNER_WATCHER_PR_MERGE_MAX_ATTEMPTS` | `watcher.pr_merge_max_attempts` |
| `PI_RUNNER_WATCHER_PR_MERGE_RETRY_INTERVAL` | `watcher.pr_merge_retry_interval` |

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

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | `.pi-runner.yaml` の `workflow` セクション | デフォルトワークフロー（推奨） |
| 2 | `.pi/workflow.yaml` | プロジェクト固有 |
| 3 | `workflows/default.yaml` | ファイルベース |
| 4 | pi-issue-runner の `workflows/default.yaml` | インストールディレクトリ |
| 5 | ビルトイン | ハードコード（plan → implement → review → merge） |

### `-w NAME` 指定時（名前付きワークフロー）

```bash
./scripts/run.sh 42 -w simple
```

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| **1** | **`.pi-runner.yaml` の `workflows.{NAME}`** | 🆕 設定ファイル内の名前付き定義（**最優先**） |
| 2 | `.pi/workflow.yaml` | プロジェクト固有（単一定義） |
| 3 | `workflows/{NAME}.yaml` | プロジェクトローカルのファイル（例: `workflows/simple.yaml`） |
| 4 | pi-issue-runner の `workflows/{NAME}.yaml` | インストールディレクトリ |
| 5 | ビルトイン | ハードコード（default/simple/thorough/ci-fix） |

> **重要**: `-w NAME` を指定した場合、**`.pi-runner.yaml` の `workflows.{NAME}` が最優先**されます。これにより、プロジェクト固有のワークフローをファイルを分散させずに `.pi-runner.yaml` 一箇所で管理できます。
> 
> **注意**: デフォルトワークフローの設定（`.pi-runner.yaml` の `workflow` セクション）は、`-w` オプション指定時には無視されます。これは、明示的なワークフロー指定が設定ファイルのデフォルトより優先されるためです。

### `-w auto` 指定時（AI 自動選択）

```bash
./scripts/run.sh 42 -w auto
```

検索順序は適用されません。`.pi-runner.yaml` の `workflows` セクション全体を読み取り、プロンプトに含めます。

- ビルトインと同名のワークフローが定義されている場合はプロジェクト定義を優先
- `workflows` セクションが未定義の場合はビルトインワークフロー一覧をフォールバックとして使用

AI は以下を参照して最適なワークフローを選択します：
- Issue の `title` と `body`
- 各ワークフローの `description`、`steps`、`context`

### 名前の重複時の優先順位

`.pi-runner.yaml` の `workflows` セクションでビルトインワークフローと同名のワークフロー（例: `ci-fix`）を定義した場合、**`.pi-runner.yaml` の定義が優先されます**。`--list-workflows` では重複を排除し、プロジェクト定義を優先表示します。

### 使い分けの指針

| 方法 | 使用シナリオ | 使用例 |
|------|-------------|--------|
| `.pi-runner.yaml` の `workflow` セクション | プロジェクト全体のデフォルトワークフローを定義 | `./scripts/run.sh 42` |
| `.pi-runner.yaml` の `workflows` セクション | 複数の名前付きワークフローを一箇所で管理（**推奨**） | `./scripts/run.sh 42 -w quick` |
| `workflows/*.yaml` | 外部ファイルとして管理したい場合 | `./scripts/run.sh 42 -w simple` |
| `.pi/workflow.yaml` | プロジェクト固有のワークフローを単一ファイルで管理（レガシー） | `-w` の有無によって動作が異なる |

**推奨構成**（複数ワークフローを使用する場合）：

```yaml
# .pi-runner.yaml
# デフォルトワークフロー
workflow:
  steps:
    - plan
    - implement
    - review
    - merge

# 名前付きワークフロー（一箇所で管理）
workflows:
  quick:
    description: 小規模修正
    steps:
      - implement
      - merge
  
  frontend:
    description: フロントエンド実装
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      技術スタック: React / Next.js
```

**使用例**：
```bash
./scripts/run.sh 42              # デフォルト（workflow）
./scripts/run.sh 42 -w quick     # workflows.quick
./scripts/run.sh 42 -w frontend  # workflows.frontend
./scripts/run.sh 42 -w auto      # AI が workflows から選択
```

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

multiplexer:
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

multiplexer:
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
- `multiplexer.*` - マルチプレクサ設定（セッション名のプレフィックス、セッション内起動設定）
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

yqがある場合はより正確にYAMLを解析します。yqがなくてもビルトインの簡易パーサーで動作します。

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
- `multiplexer.log_output`: セッション出力のファイル記録
- `pi.timeout`: タスクのタイムアウト設定
- `parallel.queue_strategy`: キュー戦略（fifo/priority）
- `parallel.auto_cleanup`: 完了後の自動クリーンアップ
- `github`: GitHub API設定
- `logging`: ログ設定
- `notifications`: 通知設定（Slack等）
- `error`: エラーハンドリング設定
- `resources`: リソース制限設定
- JSON形式の設定ファイルサポート
