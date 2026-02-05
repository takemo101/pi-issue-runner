# ワークフロー

pi-issue-runnerは、GitHub Issueの処理をワークフローとして定義し、自動化します。

## ビルトインワークフロー

### default - 完全ワークフロー

計画・実装・レビュー・マージの4ステップを実行します。

| ステップ | 説明 |
|----------|------|
| `plan` | Issue分析と実装計画の作成 |
| `implement` | コード実装とテスト |
| `review` | セルフレビューと品質確認 |
| `merge` | PR作成とマージ |

```yaml
# workflows/default.yaml
name: default
description: 完全なワークフロー（計画・実装・レビュー・マージ）
steps:
  - plan      # 実装計画の作成
  - implement # コードの実装
  - review    # セルフレビュー
  - merge     # PRの作成とマージ
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

## カスタムワークフローの作成

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
```

### 2. エージェントテンプレートの作成

**重要**: ビルトイン以外のカスタムステップを使用する場合は、対応するエージェントテンプレートを必ず作成してください。

ビルトインで提供されているステップ:
- `plan` - 実装計画の作成
- `implement` - コードの実装
- `test` - テストの実行とカバレッジ確認
- `review` - セルフレビュー
- `merge` - PRの作成とマージ

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
| 1 | `.pi-runner.yaml` の `workflow` セクション | 推奨。設定ファイル内でデフォルトワークフローを定義 |
| 2 | `.pi/workflow.yaml` | プロジェクト固有のワークフロー |
| 3 | `workflows/default.yaml` | 名前付きワークフローファイル |
| 4 | ビルトイン | `plan implement review merge` |

### `-w` オプション指定時（名前付きワークフロー）

```bash
./scripts/run.sh 42 -w simple
```

| 優先順位 | 場所 | 説明 |
|---------|------|------|
| 1 | `.pi/workflow.yaml` | 単一ワークフロー定義ファイル |
| 2 | `workflows/{name}.yaml` | 例: `-w simple` → `workflows/simple.yaml` |
| 3 | ビルトイン | `default` または `simple` |

> **重要**: `-w` オプションを指定した場合、`.pi-runner.yaml` の `workflow` セクションは**無視**されます。これにより、明示的なワークフロー指定が設定ファイルのデフォルトより優先されます。

## デフォルトワークフロー vs 名前付きワークフロー

pi-issue-runnerでは、2つの方法でワークフローを定義できます：

### デフォルトワークフロー（`.pi-runner.yaml`）

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

### 名前付きワークフロー（`workflows/*.yaml`）

複数のワークフローを定義し、`-w` オプションで切り替えて使用します。

**使用シナリオ**:
- 複数のワークフローパターンを切り替えて使用する
- 特定のタスク向けに特化したワークフロー
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
./scripts/run.sh 42 -w quick     # 簡易ワークフロー
./scripts/run.sh 42 -w thorough  # 徹底ワークフロー
```

### 使い分けのまとめ

| 観点 | デフォルトワークフロー（`.pi-runner.yaml`） | 名前付きワークフロー（`workflows/*.yaml`） |
|------|-------------------------------------------|------------------------------------------|
| **定義場所** | `.pi-runner.yaml` の `workflow` セクション | `workflows/{name}.yaml` |
| **使用法** | `./scripts/run.sh 42` | `./scripts/run.sh 42 -w {name}` |
| **用途** | 標準的な開発フロー | 特定の状況向けの代替フロー |
| **複数定義** | 不可（1つのみ） | 可（複数のYAMLファイル） |
| **優先度** | `-w` 未指定時のみ使用 | `-w` 指定時に優先 |

### 推奨される構成

一般的なプロジェクトでは、以下の構成を推奨します：

```
.pi-runner.yaml      # デフォルトワークフロー（通常の開発用）
workflows/
  simple.yaml        # 緊急時や小規模変更用（オプション）
  thorough.yaml      # 重要な変更用の徹底ワークフロー（オプション）
```

```yaml
# .pi-runner.yaml（デフォルト設定）
workflow:
  steps:
    - plan
    - implement
    - review
    - merge
```

```yaml
# workflows/simple.yaml（緊急時用）
name: simple
description: 簡易ワークフロー（小規模変更向け）
steps:
  - implement
  - merge
```

**通常の開発**:
```bash
./scripts/run.sh 42          # デフォルト（計画→実装→レビュー→マージ）
```

**緊急時の小規模修正**:
```bash
./scripts/run.sh 42 -w simple  # 簡易（実装→マージ）
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
