# ワークフロー

pi-issue-runnerは、GitHub Issueの処理をワークフローとして定義し、自動化します。

## ビルトインワークフロー

### default - 完全ワークフロー

計画・実装・テスト・レビュー・マージの5ステップを実行します。

| ステップ | 説明 |
|----------|------|
| `plan` | Issue分析と実装計画の作成 |
| `implement` | コード実装 |
| `test` | テスト実行とカバレッジ確認 |
| `review` | セルフレビューと品質確認 |
| `merge` | PR作成とマージ |

```yaml
# workflows/default.yaml
name: default
description: 標準ワークフロー（計画・実装・テスト・レビュー・マージ）
steps:
  - plan      # 実装計画の作成
  - implement # コードの実装
  - test      # テスト実行とカバレッジ確認
  - review    # セルフレビュー
  - merge     # PRの作成とマージ
context: |
  ## ワークフローの方針
  - 計画を立ててから実装を行う
  - 実装後は必ずレビューを実施
  - テストを追加・更新する
  - コミットメッセージは明確に記述する
```

### simple - 簡易ワークフロー

小規模な変更向けに、実装とマージのみを実行します。

| ステップ | 説明 |
|----------|------|
| `implement` | コード実装とテスト |
| `merge` | PR作成とマージ |

```yaml
# workflows/simple.yaml
name: simple
description: 簡易ワークフロー（実装・マージのみ）
steps:
  - implement # コードの実装
  - merge     # PRの作成とマージ
context: |
  ## ワークフローの方針
  - 小規模な修正に最適（typo修正、設定変更、ドキュメント更新等）
  - 迅速に実装してマージする
  - 明らかな変更の場合は計画・レビューをスキップ可能
```

### thorough - 徹底ワークフロー

大規模な変更や重要な機能向けに、計画・実装・テスト・レビュー・マージの5ステップを実行します。

| ステップ | 説明 |
|----------|------|
| `plan` | Issue分析と実装計画の作成 |
| `implement` | コード実装 |
| `test` | テスト実行とカバレッジ確認 |
| `review` | セルフレビューと品質確認 |
| `merge` | PR作成とマージ |

```yaml
# workflows/thorough.yaml
name: thorough
description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
steps:
  - plan
  - implement
  - test
  - review
  - merge
context: |
  ## ワークフローの方針
  - 重要な機能追加や変更に使用する
  - 詳細な計画を立ててから実装する
  - テストを必ず追加・実行する
  - レビューで品質を確保する
  - エラーハンドリングとエッジケースを考慮する
```

### ci-fix - CI修正ワークフロー

CI失敗を検出し、自動修正を試行します。マージエージェントから自動的に呼び出されることもあります。

| ステップ | 説明 |
|----------|------|
| `ci-fix` | CI失敗を検出し自動修正を試行 |

```yaml
# workflows/ci-fix.yaml
name: ci-fix
description: CI失敗を検出し自動修正を試行
steps:
  - ci-fix
context: |
  ## ワークフローの方針
  - CI失敗ログを分析して原因を特定する
  - 自動修正可能な場合は修正を適用する（フォーマット、lint等）
  - テスト失敗やビルドエラーはAIによる修正が必要
  - 最大リトライ回数に達した場合はエスカレーションする
```

**使用例**:
```bash
# 手動でCI修正を実行
./scripts/run.sh 42 --workflow ci-fix
```

> **注意**: このワークフローは通常、マージエージェントによって自動的に呼び出されます。手動実行は主にテストやデバッグ目的で使用します。

## 使用方法

### ワークフローの指定

```bash
# デフォルトワークフロー（default）
./scripts/run.sh 42

# 簡易ワークフロー
./scripts/run.sh 42 --workflow simple

# 利用可能なワークフロー一覧
./scripts/run.sh --list-workflows
```

## context フィールド: ワークフロー固有のコンテキスト注入

`context` フィールドに記述した内容は、ワークフローの全ステップのプロンプトに「Workflow Context」セクションとして注入されます。技術スタック、重視すべき点、注意事項などを記述することで、AI の実行品質を向上させます。

> **対応場所**: `context` フィールドは以下の両方でサポートされています：
> - `.pi-runner.yaml` の `workflows.{NAME}.context`
> - `workflows/{NAME}.yaml` の `context`
> 
> **優先順位**: `.pi-runner.yaml` の `workflows.{NAME}.context` > `workflows/{NAME}.yaml` の `context`

### 基本的な使い方（`.pi-runner.yaml`）

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
```

### ファイルベースの使い方（`workflows/*.yaml`）

ファイルベースでワークフローを管理する場合も、同様に `context` フィールドを使用できます：

```yaml
# workflows/backend.yaml
name: backend
description: バックエンドAPI実装
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

### プロンプトへの注入イメージ

```markdown
## Workflow: frontend

### Workflow Context

## 技術スタック
- React / Next.js / TypeScript
- TailwindCSS

## 重視すべき点
- レスポンシブデザイン
- アクセシビリティ (WCAG 2.1 AA)
- コンポーネントの再利用性
- パフォーマンス（Core Web Vitals）

---

### Step 1: Plan
...

### Step 2: Implement
...
```

`context` の内容は全ステップで共有されるため、ワークフロー全体で一貫した方針のもとで作業が進められます。

### 用途別の context 例

#### フロントエンド実装

```yaml
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
```

## agent フィールド: ワークフロー固有のエージェント設定

> **新機能**: ワークフローごとに異なるエージェント（pi, claude, opencode等）を使用できます。

`agent` フィールドを使用すると、ワークフローごとにエージェント設定（agent.type, agent.command, agent.args, agent.template）をオーバーライドできます。これにより、タスクの性質に応じて最適なエージェントやモデルを使い分けることが可能です。

> **対応場所**: `agent` フィールドは `.pi-runner.yaml` の `workflows.{NAME}.agent` でサポートされています。
> 
> **優先順位**: ワークフロー固有の設定 > グローバルな `agent` 設定 > 従来の `pi` 設定

### 基本的な使い方

```yaml
# .pi-runner.yaml

# グローバルなエージェント設定（デフォルト）
agent:
  type: pi
  args:
    - --model
    - claude-sonnet-4

# ワークフローごとのagent設定
workflows:
  # 小規模修正: 高速・低コストモデル
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5  # 軽量モデルでコスト削減
  
  # 徹底レビュー: 最高精度モデル
  thorough:
    description: 大規模機能開発（複数ファイル、新機能、アーキテクチャ変更）
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
        - claude-opus-4  # 最高精度でバグを削減
```

### 使用例

```bash
# quick ワークフローを実行（claude-haiku-4-5を使用）
./scripts/run.sh 42 -w quick

# thorough ワークフローを実行（claude-opus-4を使用）
./scripts/run.sh 42 -w thorough

# agent未指定のワークフローはグローバル設定を使用
./scripts/run.sh 42 -w simple  # グローバルのagent設定を使用
```

### エージェント設定のプロパティ

| プロパティ | 型 | 説明 |
|-----------|-----|------|
| `agent.type` | string | エージェントプリセット（pi, claude, opencode, custom） |
| `agent.command` | string | カスタムエージェントコマンド（customタイプ用） |
| `agent.args` | string[] | 追加引数（モデル指定等） |
| `agent.template` | string | コマンドテンプレート（customタイプ用） |

### 用途別のエージェント設定例

#### 高速・低コストモデルの使用

```yaml
workflows:
  quick-fix:
    description: 緊急バグ修正
    steps: [implement, merge]
    agent:
      type: pi
      args:
        - --model
        - claude-haiku-4-5
```

#### 高精度モデルの使用

```yaml
workflows:
  critical-feature:
    description: 重要機能の実装
    steps: [plan, implement, test, review, merge]
    agent:
      type: pi
      args:
        - --model
        - claude-opus-4
```

#### 別エージェントの使用

```yaml
workflows:
  experimental:
    description: 実験的機能
    steps: [plan, implement, merge]
    agent:
      type: claude  # Claude Codeを使用
      args:
        - --model
        - claude-sonnet-4
```

#### カスタムエージェントの使用

```yaml
workflows:
  custom-workflow:
    description: カスタムエージェント使用
    steps: [implement, merge]
    agent:
      type: custom
      command: my-custom-agent
      template: '{{command}} {{args}} --input "{{prompt_file}}"'
```

### agent と context の併用

`agent` と `context` は併用できます：

```yaml
workflows:
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
    steps:
      - plan
      - implement
      - review
      - merge
    agent:
      type: pi
      args:
        - --model
        - claude-sonnet-4  # フロントエンド用に最適化
  context: |
    ## 技術スタック
    - React / Next.js / TypeScript
    - TailwindCSS / CSS Modules
    
    ## 重視すべき点
    - レスポンシブデザイン（モバイルファースト）
    - アクセシビリティ (WCAG 2.1 AA)
    - コンポーネントの再利用性
    - パフォーマンス（Core Web Vitals）
    - SEO最適化（メタタグ、構造化データ）
    
    ## 避けるべき実装
    - インラインスタイル
    - グローバルスタイルの乱用
    - 過度なネスト（3階層以下を推奨）
```

#### バックエンドAPI実装

```yaml
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
    - Redis (キャッシュ)
    
    ## 重視すべき点
    - RESTful API設計（リソース指向、適切なHTTPメソッド）
    - 入力バリデーション（Zod/Joi）
    - エラーハンドリングとログ（構造化ログ）
    - ユニットテスト・統合テストの充実
    - トランザクション管理
    - セキュリティ（SQLインジェクション、XSS、CSRF対策）
    
    ## テスト要件
    - ユニットテストカバレッジ: 80%以上
    - 統合テスト: 主要なAPIエンドポイント
    - E2Eテスト: クリティカルパス
```

#### インフラIaC

```yaml
infra:
  description: インフラ構築・変更（Terraform、AWS、CI/CDパイプライン、環境構築）
  steps:
    - plan
    - implement
    - review
    - merge
  context: |
    ## 技術スタック
    - Terraform
    - AWS (EC2, RDS, S3, CloudFront, Route53)
    
    ## 重視すべき点
    - 冪等性の確保
    - セキュリティグループ・IAMの最小権限
    - terraform plan の差分確認
    - ステート管理の安全性（リモートバックエンド）
    - タグ付けの統一（環境、プロジェクト名、コスト管理）
    
    ## 避けるべき実装
    - ハードコードされたIPアドレス
    - default VPC の使用
    - 過度に広いセキュリティグループルール
```

#### 設計ドキュメント作成

```yaml
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
    - 図やテーブルを使った可視化（Mermaid推奨）
    - 将来の拡張性への言及
    - 既存コード・ドキュメントとの整合性
    - ADR形式の採用（重要な決定事項）
    
    ## テンプレート構成
    1. 背景と動機
    2. 現状の課題
    3. 提案する設計
    4. 代替案とトレードオフ
    5. 実装計画（フェーズ分け）
    6. リスクと対策
```

### ベストプラクティス

1. **技術スタックの明示**: 使用するライブラリ・フレームワーク・ツールを具体的に記載
2. **重視すべき点のリスト化**: 品質基準、非機能要件、制約を箇条書き
3. **避けるべき実装の記載**: アンチパターン、過去の失敗例を明記
4. **テスト要件の具体化**: カバレッジ目標、テスト種別を明確化
5. **プロジェクト固有の方針**: コーディング規約、命名規則、ディレクトリ構造

## カスタムステップの使用

ビルトインステップ（`plan`, `implement`, `test`, `review`, `merge`, `ci-fix`）以外に、任意のカスタムステップを定義できます。

### カスタムステップの定義

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
```

### エージェントテンプレートの作成

カスタムステップを使用する場合は、対応するエージェントテンプレートを `agents/{step}.md` に作成する必要があります。

#### agents/research.md

```markdown
# Research Agent

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

#### agents/design.md

```markdown
# Design Agent

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

### エージェントテンプレートの検索順序

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | `agents/{step}.md` | プロジェクト固有のテンプレート |
| 2 | `.pi/agents/{step}.md` | プロジェクト固有のテンプレート（代替） |
| 3 | ビルトインフォールバック | `implement` プロンプトがフォールバック |

> **注意**: カスタムステップのテンプレートが見つからない場合、ビルトインの `implement` プロンプトがフォールバックとして使用されます。最適な結果を得るには、各カスタムステップ用のテンプレートを作成してください。

### カスタムステップの例

#### validate ステップ（検証）

```yaml
# .pi-runner.yaml
workflows:
  thorough:
    description: 徹底ワークフロー
    steps:
      - plan
      - implement
      - validate  # カスタムステップ
      - test
      - review
      - merge
```

```markdown
# agents/validate.md
# Validate Agent

GitHub Issue #{{issue_number}} の実装を検証します。

## タスク
1. コードスタイルをチェック（linter実行）
2. セキュリティスキャンを実行（SAST）
3. パフォーマンステストを実行
4. 依存関係の脆弱性チェック
```

#### deploy ステップ（デプロイ）

```yaml
# .pi-runner.yaml
workflows:
  production:
    description: 本番デプロイワークフロー
    steps:
      - plan
      - implement
      - test
      - review
      - deploy  # カスタムステップ
      - merge
```

```markdown
# agents/deploy.md
# Deploy Agent

GitHub Issue #{{issue_number}} の変更をステージング環境にデプロイします。

## タスク
1. ビルドの作成
2. ステージング環境へのデプロイ
3. ヘルスチェックの実行
4. スモークテストの実行
5. デプロイ結果の記録
```

## -w auto: AI によるワークフロー自動選択

`-w auto` を指定すると（`.pi-runner.yaml` に `workflows` セクションがあれば省略でも自動適用）、AI が Issue の内容を分析して最適なワークフローを事前選択し、そのワークフローの具体的なステップ（`agents/*.md`）が展開されたプロンプトを生成します。

### 基本的な使い方

```bash
# AI が Issue #42 の内容を見てワークフローを自動選択
./scripts/run.sh 42 -w auto

# workflows セクションがあれば省略可（自動的に auto）
./scripts/run.sh 42
```

### 仕組み（2段階処理）

```
┌──────────────────────────────────────────────────────────┐
│  Stage 1: ワークフロー選択（事前処理）                       │
│                                                          │
│  ① AI選択: pi --print + 軽量モデル（haiku）で             │
│     Issue title/body とワークフロー description を照合      │
│  ② ルールベース: タイトルのプレフィックスで判定              │
│     (feat: → feature, fix: → fix, docs: → docs 等)       │
│  ③ フォールバック: default                                │
│                                                          │
│  → 選択結果: "fix"                                       │
├──────────────────────────────────────────────────────────┤
│  Stage 2: 通常のプロンプト生成                             │
│                                                          │
│  選択された "fix" ワークフローで generate_workflow_prompt   │
│  → agents/implement.md, agents/test.md 等が展開される      │
│  → context フィールドが注入される                          │
│  → 通常の -w fix と同じプロンプトが生成される               │
└──────────────────────────────────────────────────────────┘
```

1. `run.sh` が `-w auto` を検出（または `workflows` セクション定義時の省略）
2. `resolve_auto_workflow_name()` を呼び出し:
   - `pi --print` + 軽量モデルで Issue 内容と `workflows` の `description` を照合
   - 失敗時は Issue タイトルのプレフィックス（`feat:` / `fix:` / `docs:` 等）でルールベース判定
   - いずれも失敗した場合は `default` にフォールバック
3. 選択されたワークフロー名で通常の `generate_workflow_prompt()` を実行
4. `agents/*.md` のステップ別テンプレートが展開された具体的なプロンプトが生成される

### 設定

`.pi-runner.yaml` で auto 選択用のプロバイダーとモデルを指定できます：

```yaml
auto:
  provider: anthropic                # AIプロバイダー（省略時: agent設定から推定 or anthropic）
  model: claude-haiku-4-5   # 軽量モデル推奨
```

**優先順位**: `.pi-runner.yaml` の `auto` セクション > `agent.args` の `--provider` > デフォルト値

### プロンプトの生成結果

auto モードで生成されるプロンプトは、`-w fix` と直接指定した場合と**同じ内容**です:

```markdown
Implement GitHub Issue #42

## Title
ユーザー登録APIにバリデーションを追加

## Description
...

---

## Workflow: fix

### Workflow Context
## 方針
- 回帰テストの追加を検討すること
- 修正範囲を最小限に抑える
...

### Step 1: Implement
（agents/implement.md の具体的な手順）

### Step 2: Test
（agents/test.md の具体的な手順）

### Step 3: Review
（agents/review.md の具体的な手順）

### Step 4: Merge
（agents/merge.md の具体的な手順）
```

### description の書き方（AI 判断精度への影響）

AI の自動選択精度を向上させるには、`description` を具体的に記述することが重要です。

#### 悪い例（曖昧）

```yaml
workflows:
  quick:
    description: 簡単なタスク  # ❌ 曖昧すぎる
  
  complex:
    description: 複雑なタスク  # ❌ 何が複雑かわからない
```

#### 良い例（具体的）

```yaml
workflows:
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）  # ✅ 対象が明確
  
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）  # ✅ 技術スタックと対象が明確
  
  backend:
    description: バックエンドAPI実装（DB操作、認証、ビジネスロジック、サーバーサイド処理）  # ✅ 実装領域が明確
```

#### ベストプラクティス

1. **対象範囲の明示**: どのような変更が対象か（小規模/大規模、領域）
2. **技術スタックの記載**: 使用する技術（React, Node.js, Terraform等）
3. **具体例の列挙**: タイポ修正、API実装、UI変更など
4. **規模感の表現**: 1ファイル、複数ファイル、新機能、アーキテクチャ変更など

### 使用例

```yaml
# .pi-runner.yaml
workflows:
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
  
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      技術スタック: React / Next.js / TypeScript / TailwindCSS
  
  backend:
    description: バックエンドAPI実装（DB操作、認証、ビジネスロジック、サーバーサイド処理）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
    context: |
      技術スタック: Node.js / Express / TypeScript / PostgreSQL
  
  infra:
    description: インフラ構築・変更（Terraform、AWS、CI/CDパイプライン、環境構築）
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      技術スタック: Terraform / AWS
  
  design:
    description: 設計ドキュメント作成（技術調査、アーキテクチャ設計、ADR、仕様書）
    steps:
      - research
      - design
      - review
      - merge
    context: |
      成果物: docs/ 以下のMarkdownドキュメント
```

**実行例**:

```bash
# Issue #42「READMEのtypo修正」→ quick を選択
./scripts/run.sh 42 -w auto

# Issue #43「ユーザー登録APIの追加」→ backend を選択
./scripts/run.sh 43 -w auto

# Issue #44「ログインフォームのUIリニューアル」→ frontend を選択
./scripts/run.sh 44 -w auto

# Issue #45「AWSのVPC設定変更」→ infra を選択
./scripts/run.sh 45 -w auto
```

### フォールバック

`.pi-runner.yaml` に `workflows` セクションが定義されていない場合、ビルトインワークフロー（`default`, `simple`, `thorough`, `ci-fix`）が選択対象になります。

## カスタムワークフローの作成（ファイルベース）

従来の方法（`workflows/*.yaml`）も引き続きサポートされます。

### 1. ワークフローファイルの作成

`workflows/` ディレクトリにYAMLファイルを作成します：

```yaml
# workflows/custom-example.yaml
name: custom-example
description: カスタムワークフロー例（計画・実装・検証・レビュー・マージ）
steps:
  - plan
  - implement
  - validate  # カスタムステップ
  - review
  - merge
context: |
  ## プロジェクト固有の設定
  - カスタム検証ルールを適用
```

### 2. エージェントテンプレートの作成

**重要**: ビルトイン以外のカスタムステップを使用する場合は、対応するエージェントテンプレートを必ず作成してください。

ビルトインで提供されているステップ:
- `plan` - 実装計画の作成
- `implement` - コードの実装
- `test` - テストの実行とカバレッジ確認
- `review` - セルフレビュー
- `merge` - PRの作成とマージ
- `ci-fix` - CI失敗の修正

`agents/` ディレクトリにMarkdownファイルを作成します：

```markdown
# agents/validate.md（カスタムステップの例）
# Validate Agent

GitHub Issue #{{issue_number}} の実装を検証します。

## タスク
1. コードスタイルをチェック
2. セキュリティスキャンを実行
3. パフォーマンステストを実行
```

### 3. カスタムワークフローの使用

```bash
./scripts/run.sh 42 --workflow custom-example
```

> **注意**: カスタムワークフローで定義したステップに対応するエージェントテンプレートが存在しない場合、ビルトインのフォールバックプロンプトが使用されます。最適な結果を得るには、各ステップ用のテンプレートを作成してください。

## ワークフロー検索順序

ワークフローの検索順序は、`-w/--workflow` オプションの有無によって異なります。

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

## デフォルトワークフロー vs 名前付きワークフロー

pi-issue-runnerでは、3つの方法でワークフローを定義できます：

### デフォルトワークフロー（`.pi-runner.yaml` の `workflow`）

プロジェクトの標準的なワークフローを `.pi-runner.yaml` に定義します。`-w` オプションを省略した場合に自動的に使用されます。

**使用シナリオ**:
- チーム全体で統一されたワークフローを使用する
- 通常の開発フローに合わせた設定
- プロジェクト固有のステップ構成

```yaml
# .pi-runner.yaml
workflow:
  steps:
    - plan
    - implement
    - review
    - merge
```

**実行**:
```bash
# -w オプションなしでデフォルトワークフローを使用
./scripts/run.sh 42
```

### 名前付きワークフロー（`.pi-runner.yaml` の `workflows`）

> **新機能**: 複数の名前付きワークフローを `.pi-runner.yaml` 内で定義できます。

複数のワークフローを `.pi-runner.yaml` の `workflows` セクションで定義し、`-w` オプションで切り替えて使用します。

**使用シナリオ**:
- 複数のワークフローパターンを一箇所で管理したい
- 領域別（フロントエンド/バックエンド/インフラ等）にワークフローを切り替える
- Issue の種類に応じて最適なワークフローを選択する
- AI にワークフローを自動選択させる（`-w auto`）

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
```

**実行**:
```bash
./scripts/run.sh 42 -w quick     # quick ワークフロー
./scripts/run.sh 42 -w frontend  # frontend ワークフロー
./scripts/run.sh 42 -w auto      # AI が自動選択

# 利用可能なワークフロー一覧
./scripts/run.sh --list-workflows
```

### 名前付きワークフロー（`workflows/*.yaml`）

外部ファイルとして管理する従来の方法も引き続きサポートされます。

**使用シナリオ**:
- ファイルを分散して管理したい
- バージョン管理で個別に追跡したい
- 実験的なワークフローを試す

```yaml
# workflows/quick.yaml
name: quick
description: 緊急対応用（実装のみ）
steps:
  - implement
```

```yaml
# workflows/thorough.yaml
name: thorough
description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
steps:
  - plan
  - implement
  - test
  - review
  - merge
```

**実行**:
```bash
./scripts/run.sh 42 -w quick     # workflows/quick.yaml
./scripts/run.sh 42 -w thorough  # workflows/thorough.yaml
```

> **注意**: `-w NAME` 指定時、`.pi-runner.yaml` の `workflows.{NAME}` が `workflows/{NAME}.yaml` より優先されます。

### 使い分けのまとめ

| 観点 | デフォルトワークフロー（`workflow`） | 名前付きワークフロー（`workflows`） | ファイルベース（`workflows/*.yaml`） |
|------|-------------------------------------|-----------------------------------|----------------------------------|
| **定義場所** | `.pi-runner.yaml` の `workflow` | `.pi-runner.yaml` の `workflows` | `workflows/{name}.yaml` |
| **使用法** | `./scripts/run.sh 42` | `./scripts/run.sh 42 -w {name}` | `./scripts/run.sh 42 -w {name}` |
| **用途** | 標準的な開発フロー | 状況別の複数パターン（**推奨**） | ファイル分散管理 |
| **複数定義** | 不可（1つのみ） | 可（複数定義） | 可（複数ファイル） |
| **優先度** | `-w` 未指定時のみ | `-w {name}` 時に最優先 | `-w {name}` 時に2番目 |
| **AI選択** | 対象外 | `-w auto` で選択対象 | `-w auto` で選択対象（`workflows` がない場合） |
| **context** | 不可 | 可（推奨） | 可 |

### 推奨される構成

一般的なプロジェクトでは、以下の構成を推奨します：

```yaml
# .pi-runner.yaml（一箇所で管理）

# デフォルトワークフロー
workflow:
  steps:
    - plan
    - implement
    - review
    - merge

# 名前付きワークフロー（複数定義）
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
      - アクセシビリティ
      - コンポーネントの再利用性
  
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

**使用例**：
```bash
./scripts/run.sh 42              # デフォルト（workflow）
./scripts/run.sh 42 -w quick     # 小規模修正
./scripts/run.sh 42 -w frontend  # フロントエンド実装（context付き）
./scripts/run.sh 42 -w auto      # AI が自動選択
```

## エージェントテンプレート

各ステップには対応するエージェントテンプレート（`agents/{step}.md`）が使用されます。

### エージェント検索順序

1. `agents/{step}.md`
2. `.pi/agents/{step}.md`
3. ビルトインエージェント

### テンプレート変数

ワークフローとエージェントテンプレートで使用可能な変数：

| 変数 | 説明 |
|------|------|
| `{{issue_number}}` | GitHub Issue番号 |
| `{{issue_title}}` | Issueタイトル |
| `{{branch_name}}` | ブランチ名 |
| `{{worktree_path}}` | worktreeのパス |
| `{{workflow_name}}` | ワークフロー名 |
| `{{step_name}}` | 現在のステップ名 |

## ビルトインエージェント

| ステップ | ファイル | 説明 |
|----------|----------|------|
| plan | `agents/plan.md` | 実装計画を作成 |
| implement | `agents/implement.md` | コードを実装 |
| test | `agents/test.md` | テスト実行とカバレッジ確認 |
| review | `agents/review.md` | セルフレビューを実施 |
| merge | `agents/merge.md` | PRを作成してマージ |

## プロジェクト設定でのワークフロー定義（デフォルトワークフロー）

`.pi-runner.yaml` でワークフローを直接定義することで、**デフォルトワークフロー**を設定できます。これは `-w` オプションを省略した場合に使用されます。

```yaml
# .pi-runner.yaml
workflow:
  steps:
    - plan
    - implement
    - review
    - merge
```

> **注意**: `.pi-runner.yaml` の `workflow` セクションで `name` フィールドは無視されます。このワークフローは「デフォルト」として機能し、名前付きワークフローとして使用することはできません。名前付きワークフローが必要な場合は `workflows/*.yaml` ファイルを作成してください。

## 関連ドキュメント

- [設定ファイル](./configuration.md) - ワークフロー設定の詳細
- [Hook機能](./hooks.md) - ワークフローイベントでのカスタム処理
- [仕様書](./SPECIFICATION.md) - 完全な技術仕様
