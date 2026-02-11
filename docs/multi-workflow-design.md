# 設計書: `.pi-runner.yaml` での複数ワークフロー定義

**作成日**: 2026-02-06
**ステータス**: Implemented（実装済み）

---

## 1. 背景と動機

### 現状の課題

pi-issue-runnerでは、Issueの種類に関わらず同一のワークフローが適用される。実際のプロジェクトでは、Issueの性質によって最適なワークフローは異なる：

| Issueの種類 | 現状 | 理想 |
|------------|------|------|
| バグ修正（小規模） | plan → implement → review → merge | implement → merge |
| 新機能（大規模） | plan → implement → review → merge | plan → implement → test → review → merge |
| ドキュメント修正 | plan → implement → review → merge | implement → merge（レビュー不要） |
| フロントエンド実装 | plan → implement → review → merge | plan → implement → review → merge + UIコンテキスト |
| バックエンド実装 | plan → implement → review → merge | plan → implement → test → review → merge + APIコンテキスト |
| インフラIaC | plan → implement → review → merge | plan → implement → review → merge + IaCコンテキスト |
| 設計ドキュメント | plan → implement → review → merge | research → design → review → merge + 設計コンテキスト |
| CI修正 | plan → implement → review → merge | ci-fix |

現在は `workflows/*.yaml` に個別ファイルを作成すれば `--workflow` で切り替え可能だが、ファイルが散在し管理しにくい。`.pi-runner.yaml` 一箇所で全ワークフローを定義・管理したい。

さらに、ステップ構成が同じでも **実装の領域（フロントエンド/バックエンド/インフラ等）に応じたコンテキストや指示** を注入したいケースがある。

### oh-my-opencode からの着想

[oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode) は「カテゴリ」という概念でタスクの性質に応じた実行戦略を切り替える：

| カテゴリ | 用途 | モデル | プロンプト補足 |
|---------|------|--------|--------------|
| `visual-engineering` | フロントエンド・UI | Gemini 3 Pro | デザイン重視の指示 |
| `ultrabrain` | 深い論理的推論 | GPT-5.3 Codex | 戦略的アドバイザー |
| `deep` | 自律的問題解決 | GPT-5.3 Codex | 自律実行の指示 |
| `quick` | 小規模タスク | Claude Haiku 4.5 | 最小限の実装指示 |
| `writing` | ドキュメント | Gemini 3 Flash | 文章品質重視 |

特に重要なのが **`CATEGORY_PROMPT_APPENDS`** の仕組みで、カテゴリごとに固有のコンテキスト（技術スタック、重視すべき点、実行方針）をプロンプトに注入する。これにより同じ「タスク実行」でもカテゴリに応じた振る舞いが実現される。

この思想を pi-issue-runner に取り入れ、以下を実現する：

1. **ワークフロー（ステップ構成）の切り替え** — Issueの規模・種類に応じて
2. **コンテキスト注入** — 実装領域に応じた技術スタック・方針の注入
3. **AI によるワークフロー自動選択** — Issue内容から最適なワークフローをAIが判断

---

## 2. 設計

### 2.1 設定形式

`.pi-runner.yaml` に `workflows`（複数形）セクションを新設する。各ワークフローは `description`（説明）、`steps`（ステップ構成）、`context`（コンテキスト注入）を持つ。

```yaml
# .pi-runner.yaml

# ============================
# デフォルトワークフロー（従来互換）
# ============================
# -w オプション未指定時に使用される
workflow:
  steps:
    - plan
    - implement
    - review
    - merge

# ============================
# 名前付きワークフロー（新機能）
# ============================
# -w オプションで選択、または -w auto でAI自動選択
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

  # フロントエンド実装向け
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

  # バックエンド実装向け
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

  # インフラIaC向け
  infra:
    description: インフラ構築・変更（Terraform、AWS、CI/CDパイプライン、環境構築）
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      ## 技術スタック
      - Terraform / AWS

      ## 重視すべき点
      - 冪等性の確保
      - セキュリティグループ・IAMの最小権限
      - terraform plan の差分確認
      - ステート管理の安全性

  # ドキュメント修正向け
  docs:
    description: ドキュメント更新（README、API仕様書、技術ドキュメント）
    steps:
      - implement
      - merge

  # 設計ドキュメント作成向け
  design:
    description: 設計ドキュメント作成（技術調査、アーキテクチャ設計、ADR、仕様書）
    steps:
      - research
      - design
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

  # CI修正向け
  ci-fix:
    description: CI失敗の自動修正（テスト失敗、ビルドエラー、lint警告）
    steps:
      - ci-fix
```

### 2.2 カスタムステップとエージェントテンプレート

ワークフローの `steps` にはビルトインステップ（`plan`, `implement`, `test`, `review`, `merge`, `ci-fix`）以外に **任意のカスタムステップ** を定義できる。カスタムステップを使う場合は、対応するエージェントテンプレートを `agents/` ディレクトリに配置する。

上記の `design` ワークフローでは `research` と `design` というカスタムステップを使用している。対応するエージェントテンプレートの例：

```markdown
# agents/research.md
GitHub Issue #{{issue_number}} に関する技術調査を行います。

## コンテキスト
- **Issue**: #{{issue_number}} {{issue_title}}
- **ブランチ**: {{branch_name}}
- **Worktree**: {{worktree_path}}

## タスク
1. Issue の要件を分析し、解決すべき課題を明確化
2. 関連する既存コード・ドキュメントを調査
3. 外部の技術ドキュメント・ベストプラクティスを確認
4. 技術的な選択肢と制約を洗い出す
5. 調査結果を {{worktree_path}}/docs/ 以下にメモとしてまとめる

## 注意
- この段階ではコードの実装は行わない
- 調査結果は次の design ステップで使用される
```

```markdown
# agents/design.md
GitHub Issue #{{issue_number}} の設計ドキュメントを作成します。

## コンテキスト
- **Issue**: #{{issue_number}} {{issue_title}}
- **ブランチ**: {{branch_name}}
- **Worktree**: {{worktree_path}}

## タスク
1. research ステップの調査結果を確認
2. 設計方針を決定し、代替案とトレードオフを整理
3. docs/ 以下に設計ドキュメントを作成
   - 背景と課題
   - 設計方針
   - アーキテクチャ（必要に応じて図・テーブルで可視化）
   - API仕様・データモデル（該当する場合）
   - 代替案とトレードオフ
   - 将来の拡張性
4. 既存ドキュメントとの整合性を確認

## 注意
- コードの変更は原則行わない（設計ドキュメントのみ）
- 不明点は Issue のコメントを参照し、合理的な判断を行う
```

> **エージェントテンプレートの検索順序**: `agents/{step}.md` → `.pi/agents/{step}.md` → pi-issue-runner の `agents/{step}.md` → ビルトインフォールバック。カスタムステップのテンプレートが見つからない場合はビルトインの `implement` プロンプトがフォールバックとして使用される。

### 2.3 `context` フィールド

各ワークフローにオプションの `context` フィールドを持たせる。これはプロンプト生成時に **「Workflow Context」セクション** として全ステップに共通で注入される。

oh-my-opencode の `CATEGORY_PROMPT_APPENDS` に相当する機能で、ワークフローの種類に応じた技術スタック・方針・注意点をAIに伝える。

#### プロンプトへの注入イメージ

```markdown
## Workflow: frontend

...

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
### Step 2: Implement
...
```

### 2.4 `description` フィールドと `--list-workflows`

各ワークフローのオプション `description` フィールドは2つの用途で使われる：

1. **`--list-workflows` での表示** — 人間がワークフローを選ぶときの参考情報
2. **`-w auto` での AI 判断材料** — AIがIssue内容と照合して最適なワークフローを選択する際の判断基準

```bash
$ ./scripts/run.sh --list-workflows
=== Builtin workflows ===
default: 完全なワークフロー（計画・実装・レビュー・マージ）
simple: 簡易ワークフロー（実装・マージのみ）
thorough: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
=== Project workflows (.pi-runner.yaml) ===
quick: 小規模修正（typo、設定変更、1ファイル程度の変更）
frontend: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
backend: バックエンドAPI実装（DB操作、認証、ビジネスロジック、サーバーサイド処理）
infra: インフラ構築・変更（Terraform、AWS、CI/CDパイプライン、環境構築）
design: 設計ドキュメント作成（技術調査、アーキテクチャ設計、ADR、仕様書）
docs: ドキュメント更新（README、API仕様書、技術ドキュメント）
ci-fix: CI失敗の自動修正（テスト失敗、ビルドエラー、lint警告）  ※ビルトインをオーバーライド
```

> **ポイント**: `description` を具体的に書くほど AI の自動選択精度が向上する。曖昧な description は誤選択の原因になるため、対象となるタスクの特徴を明確に記載すること。

### 2.5 `-w auto`: AI によるワークフロー自動選択

`-w auto` を指定すると、**AI が Issue の内容を分析して最適なワークフローを自動選択** する。

```bash
# AI が Issue #42 の内容を見てワークフローを自動選択
./scripts/run.sh 42 -w auto
```

#### 仕組み

```
1. run.sh が -w auto を検出
2. .pi-runner.yaml の workflows セクションから全ワークフロー情報を収集
3. プロンプトに「Workflow Selection」セクションを生成
   - 各ワークフローの name, description, steps, context を列挙
4. AI が Issue の title/body を分析し、最適なワークフローを選択
5. 選択したワークフローの steps に従い、context を参考にして実行
```

#### プロンプトへの注入イメージ（`-w auto` 時）

```markdown
Implement GitHub Issue #42

## Title
ユーザー登録APIにバリデーションを追加

## Description
メールアドレスの形式チェックとパスワード強度チェックを実装してください。

---

## Workflow Selection

以下のワークフローから、このIssueに最も適切なものを1つ選択してください。
選択したワークフローの Steps に従い、Context の指示を参考にして実行してください。

### Available Workflows

| Name | Description | Steps |
|------|------------|-------|
| quick | 小規模修正（typo、設定変更、1ファイル程度の変更） | implement → merge |
| thorough | 大規模機能開発（複数ファイル、新機能、アーキテクチャ変更） | plan → implement → test → review → merge |
| frontend | フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング） | plan → implement → review → merge |
| backend | バックエンドAPI実装（DB操作、認証、ビジネスロジック） | plan → implement → test → review → merge |
| infra | インフラ構築・変更（Terraform、AWS、CI/CDパイプライン） | plan → implement → review → merge |
| design | 設計ドキュメント作成（技術調査、アーキテクチャ設計、ADR、仕様書） | research → design → review → merge |
| docs | ドキュメント更新（README、API仕様書、技術ドキュメント） | implement → merge |
| ci-fix | CI失敗の自動修正（テスト失敗、ビルドエラー、lint警告） | ci-fix |

### Workflow Details

<details>
<summary>quick</summary>

**Steps**: implement → merge
**Context**: (なし)
</details>

<details>
<summary>backend</summary>

**Steps**: plan → implement → test → review → merge
**Context**:
## 技術スタック
- Node.js / Express / TypeScript
- PostgreSQL / Prisma

## 重視すべき点
- RESTful API設計
- 入力バリデーション
...
</details>

...（他のワークフローも同様）

---

**指示**: Issue の内容を分析し、上記から最も適切なワークフローを選択してください。
選択理由を簡潔に述べた後、そのワークフローの Steps と Context に従って実行を開始してください。
```

#### 設計判断: なぜ2段階AI呼び出しではなくプロンプト内選択か

| 方式 | メリット | デメリット |
|------|---------|-----------|
| **2段階方式**（先にAI呼び出しでワークフロー選択→その結果でプロンプト生成） | ステップ構成が確定した状態でプロンプト生成できる | run.sh にAI呼び出しが必要、アーキテクチャ変更大 |
| **プロンプト内選択**（全ワークフロー情報をプロンプトに含め、AI が選択・実行） | run.sh の変更が最小限、1セッションで完結 | トークン消費が少し増える |

**プロンプト内選択を採用する**。理由：

1. run.sh のアーキテクチャ変更が不要（プロンプト生成の変更のみ）
2. AI 呼び出しの二重化によるレイテンシ・コスト増を回避
3. AI は Issue の内容を直接見ながら選択できるため、コンテキスト理解が正確
4. ワークフロー情報は数百トークン程度で、全体のプロンプト量に対する影響は軽微

### 2.6 明示的指定（`-w NAME`）の検索優先順位

#### `-w` 未指定時（デフォルトワークフロー）— 変更なし

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | `.pi-runner.yaml` の `workflow` セクション | デフォルトワークフロー |
| 2 | `.pi/workflow.yaml` | プロジェクト固有 |
| 3 | `workflows/default.yaml` | ファイルベース |
| 4 | pi-issue-runner の `workflows/default.yaml` | インストールディレクトリ |
| 5 | ビルトイン `default` | ハードコード |

#### `-w NAME` 指定時（名前付きワークフロー）— **変更あり**

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | **`.pi-runner.yaml` の `workflows.{NAME}`** | 🆕 設定ファイル内の名前付き定義 |
| 2 | `.pi/workflow.yaml` | プロジェクト固有（単一定義） |
| 3 | `workflows/{NAME}.yaml` | プロジェクトローカルのファイル |
| 4 | pi-issue-runner の `workflows/{NAME}.yaml` | インストールディレクトリ |
| 5 | ビルトイン `{NAME}` | ハードコード（default/simple） |

#### 名前の重複時の優先順位

`.pi-runner.yaml` の `workflows` セクションでビルトインワークフローと同名のワークフロー（例: `ci-fix`）を定義した場合、**`.pi-runner.yaml` の定義が優先される**。`--list-workflows` では重複を排除し、プロジェクト定義を優先表示する。

#### `-w auto` 指定時（AI自動選択）

検索順序は適用されない。`.pi-runner.yaml` の `workflows` セクション全体を読み取り、プロンプトに含める。ビルトインと同名のワークフローが定義されている場合はプロジェクト定義を優先する。`workflows` セクションが未定義の場合はビルトインワークフロー一覧をフォールバックとして使用する。

### 2.7 内部設計

#### 返り値の拡張

`find_workflow_file()` の返り値に新しい形式を追加する：

| 返り値の形式 | 意味 |
|-------------|------|
| `/path/to/file.yaml` | YAMLファイル（従来通り） |
| `builtin:NAME` | ビルトインワークフロー（従来通り） |
| **`config-workflow:NAME`** | 🆕 `.pi-runner.yaml` の `workflows.{NAME}` |
| **`auto`** | 🆕 AI自動選択モード |

`get_workflow_steps()` は `config-workflow:NAME` を受け取ったとき、設定ファイルから `workflows.{NAME}.steps` を読み取る。

`auto` の場合、プロンプト生成側（`workflow-prompt.sh`）で特別な処理を行う。

#### ワークフロー情報の取得関数（新規）

`-w auto` とプロンプト生成のために、以下の関数を追加する：

```bash
# 全ワークフロー情報を取得（auto モード用）
# 出力: name\tdescription\tsteps\tcontext（タブ区切り、1行1ワークフロー）
get_all_workflows_info() {
    local project_root="${1:-.}"
    # .pi-runner.yaml の workflows セクションを走査
    # ビルトインワークフローも含める
}

# 特定ワークフローの context を取得
get_workflow_context() {
    local workflow_file="$1"
    local workflow_name="${2:-}"
    # config-workflow:NAME の場合: .pi-runner.yaml から workflows.{NAME}.context を取得
    # 通常のYAMLファイルの場合: .context キーを取得
}
```

#### YAML パーサーの拡張

現在の簡易パーサー（`yaml.sh`）は2階層（`section.key`）までサポート。`workflows.quick.steps` は3階層になるため、簡易パーサーの拡張が必要。

**方針**: `yaml_get`, `yaml_get_array`, `yaml_exists` で3階層のドット区切りパスを処理できるよう拡張する。`yq` がインストールされている環境では追加対応不要（yqはネイティブに対応）。

##### 3階層のYAML構造

```yaml
workflows:        # レベル1: インデントなし
  quick:          # レベル2: 2スペース
    description: ... # レベル3: 4スペース（値あり）
    steps:        # レベル3: 4スペース（配列の親）
      - implement # レベル4: 6スペース（配列要素）
      - merge
    context: |    # レベル3: 4スペース（複数行値）
      ...
```

簡易パーサーでは、インデントの深さでレベルを判定し、3階層目のキーとその値（スカラー値・配列・複数行テキスト）を取得できるようにする。

##### `context`（複数行テキスト）の扱い

YAMLの `|`（リテラルブロック）記法で記述された複数行テキストの取得が必要。簡易パーサーでの対応方針：

- `yq` がある場合: `yq -r '.workflows.frontend.context'` でそのまま取得可能
- 簡易パーサーの場合: `context: |` の行を検出した後、次のキー（同レベル以上のインデント）が現れるまでの行を連結して返す

#### workflows セクションのキー列挙

`-w auto` および `--list-workflows` のために、`workflows` セクション直下のキー一覧（ワークフロー名の列挙）が必要。

```bash
# workflows セクションのキー一覧を取得
# 出力: 各行にワークフロー名
yaml_get_keys() {
    local file="$1"
    local path="$2"  # 例: ".workflows"
    # yq: yq -r '.workflows | keys[]'
    # 簡易パーサー: workflows: セクション直下の 2スペースインデントキーを列挙
}
```

---

## 3. 影響範囲

### 変更が必要なファイル

| # | ファイル | 変更内容 | 規模 |
|---|---------|---------|------|
| 1 | `lib/yaml.sh` | 簡易パーサーで3階層パス対応、複数行テキスト対応、`yaml_get_keys()` 追加 | 中 |
| 2 | `lib/workflow-finder.sh` | `find_workflow_file()` に `workflows.{NAME}` 検索と `auto` モード追加 | 小 |
| 3 | `lib/workflow-loader.sh` | `get_workflow_steps()` で `config-workflow:NAME` 処理、`get_workflow_context()` 追加、`get_all_workflows_info()` 追加 | 中 |
| 4 | `lib/workflow-prompt.sh` | `generate_workflow_prompt()` に context 注入と auto モードのプロンプト生成を追加 | 中 |
| 5 | `lib/workflow.sh` | `list_available_workflows()` で `.pi-runner.yaml` の `workflows` も列挙 | 小 |
| 6 | `test/lib/yaml.bats` | 3階層パース、複数行テキスト、`yaml_get_keys()` のテスト追加 | 中 |
| 7 | `test/lib/workflow-finder.bats` | `workflows.{NAME}` 検索、`auto` モードのテスト追加 | 中 |
| 8 | `test/lib/workflow-loader.bats` | `config-workflow:NAME` 処理、context 取得、auto 情報取得のテスト追加 | 中 |
| 9 | `test/lib/workflow-prompt.bats` | context 注入、auto モードプロンプト生成のテスト追加 | 中 |
| 10 | `test/lib/workflow.bats` | 統合テスト追加 | 小 |
| 11 | `docs/configuration.md` | `workflows` セクション、`context`、`-w auto` のドキュメント追加 | 中 |
| 12 | `docs/workflows.md` | ワークフロードキュメント更新 | 中 |

### 変更不要なファイル

| ファイル | 理由 |
|---------|------|
| `scripts/run.sh` | `-w auto` は文字列として `workflow_name` に渡されるだけ。パース変更不要 |
| `lib/config.sh` | `workflows` セクションは config.sh では読み込まない |
| `scripts/run-batch.sh` | `--workflow` をそのまま渡すだけ |

---

## 4. 後方互換性

| 項目 | 互換性 | 説明 |
|------|--------|------|
| `workflow:` セクション（単数形） | ✅ 完全互換 | デフォルトワークフローとして引き続き動作 |
| `workflows/*.yaml` ファイル | ✅ 完全互換 | 検索順位は下がるが引き続き動作 |
| `-w NAME` オプション | ✅ 互換 | 新たに `.pi-runner.yaml` 内も検索対象に追加 |
| `-w auto` オプション | 🆕 新規追加 | 既存の動作に影響なし |
| 簡易YAMLパーサー（yqなし環境） | ✅ 対応 | 3階層・複数行テキストサポートを追加 |
| `--list-workflows` | ✅ 拡張 | `.pi-runner.yaml` のワークフローも表示 |

**破壊的変更**: なし

---

## 5. 実装順序

```
Phase 1: 基盤（yaml.sh の拡張）
  ├── 3階層パス対応
  ├── 複数行テキスト（リテラルブロック）取得
  ├── yaml_get_keys() 追加
  └── test/lib/yaml.bats のテスト追加
      ↓
Phase 2: コアロジック（ワークフロー検索・読み込み）
  ├── lib/workflow-finder.sh: config-workflow:NAME 検索、auto 対応
  ├── lib/workflow-loader.sh: steps 取得、context 取得、全ワークフロー情報取得
  ├── lib/workflow.sh: list 更新
  └── 対応するテスト追加
      ↓
Phase 3: プロンプト生成
  ├── lib/workflow-prompt.sh: context 注入、auto モードプロンプト
  └── test/lib/workflow-prompt.bats のテスト追加
      ↓
Phase 4: ドキュメント
  ├── docs/configuration.md の更新
  └── docs/workflows.md の更新
```

---

## 6. テスト計画

### yaml.sh のテスト

```bash
# 3階層パスのテスト
@test "yaml_get_array parses 3-level path: workflows.quick.steps"
@test "yaml_get parses 3-level path: workflows.quick.description"
@test "yaml_exists checks 3-level path: workflows.quick"
@test "yaml_exists returns false for nonexistent 3-level path"

# 複数行テキストのテスト
@test "yaml_get returns multiline text with literal block scalar"

# キー列挙のテスト
@test "yaml_get_keys lists workflow names under workflows section"
@test "yaml_get_keys returns empty for nonexistent section"
```

### workflow-finder.sh のテスト

```bash
# .pi-runner.yaml の workflows セクション
@test "find_workflow_file returns config-workflow:quick when workflows.quick defined"
@test "find_workflow_file prioritizes workflows section over workflows/*.yaml files"
@test "find_workflow_file falls back to file when workflow not in workflows section"
@test "find_workflow_file ignores workflows section for default (uses workflow section)"
@test "find_workflow_file returns auto for -w auto"
```

### workflow-loader.sh のテスト

```bash
# config-workflow:NAME 処理
@test "get_workflow_steps returns steps for config-workflow:quick"
@test "get_workflow_steps returns builtin when config-workflow steps empty"

# context 取得
@test "get_workflow_context returns context for config-workflow"
@test "get_workflow_context returns empty when no context defined"

# 全ワークフロー情報
@test "get_all_workflows_info lists all workflows with description and steps"
```

### workflow-prompt.sh のテスト

```bash
# context 注入
@test "generate_workflow_prompt includes context section when context defined"
@test "generate_workflow_prompt omits context section when no context"

# auto モード
@test "generate_workflow_prompt generates selection prompt for auto mode"
@test "auto mode prompt includes all workflow descriptions"
@test "auto mode prompt includes workflow steps and context"
```

### workflow.sh のテスト

```bash
# 一覧表示
@test "list_available_workflows shows workflows from .pi-runner.yaml"
@test "list_available_workflows shows description from .pi-runner.yaml"
```

---

## 7. 将来の拡張ポイント（スコープ外）

oh-my-opencode のカテゴリシステムに着想を得た、将来的な拡張の可能性：

### 7.1 ワークフローごとのエージェント設定

```yaml
# 将来の構想（今回は実装しない）
workflows:
  quick:
    steps:
      - implement
      - merge
    agent:
      type: claude
      args: ["--model", "haiku"]  # 軽量モデルで高速に

  thorough:
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    agent:
      type: claude
      args: ["--model", "opus"]  # 高性能モデルで確実に
```

### 7.2 ステップごとのエージェントテンプレートオーバーライド

```yaml
# 将来の構想（今回は実装しない）
workflows:
  frontend:
    steps:
      - plan
      - implement
      - review
      - merge
    agents:
      implement: agents/frontend-implement.md
      review: agents/frontend-review.md
```

### 7.3 Issue ラベルによるワークフロー自動選択（ルールベース）

```yaml
# 将来の構想（今回は実装しない）
workflow_rules:
  - label: "bug"
    workflow: quick
  - label: "enhancement"
    workflow: thorough
  - label: "frontend"
    workflow: frontend
  - label: "documentation"
    workflow: docs
  - default: default
```

AI による自動選択（`-w auto`）との使い分け：
- **ルールベース**: 確実性重視。ラベルが適切に付与されている前提
- **AI 選択**: 柔軟性重視。ラベルが不完全でもIssue本文から推定

これらはいずれも今回の `workflows` セクションと `context` フィールドの基盤の上に自然に構築できる。

---

## 8. まとめ

- `.pi-runner.yaml` に `workflows`（複数形）セクションを追加し、名前付き複数ワークフローを定義可能にする
- 各ワークフローに `context` フィールドを持たせ、実装領域に応じたコンテキスト（技術スタック・方針）を注入可能にする
- `-w auto` モードにより、AI が Issue の内容と各ワークフローの `description` を照合して最適なワークフローを自動選択する
- 既存の `workflow`（単数形）セクションとの後方互換性を完全に維持する
- oh-my-opencode のカテゴリシステムを参考に、将来的なエージェント設定・ルールベース選択にも拡張可能な設計とする
