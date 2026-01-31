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

### 2. エージェントテンプレートの作成

各ステップには対応するエージェントテンプレートが必要です。`agents/` ディレクトリにMarkdownファイルを作成します：

```markdown
# agents/test.md
# Test Agent

GitHub Issue #{{issue_number}} のテストを実行します。

## タスク
1. 単体テストを実行
2. 結合テストを実行
3. カバレッジレポートを確認
```

### 3. カスタムワークフローの使用

```bash
./scripts/run.sh 42 --workflow thorough
```

## ワークフロー検索順序

ワークフローは以下の優先順位で検索されます：

1. `.pi-runner.yaml` の `workflow` セクション
2. `.pi/workflow.yaml`
3. `workflows/{name}.yaml`
4. ビルトイン定義

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
| review | `agents/review.md` | セルフレビューを実施 |
| merge | `agents/merge.md` | PRを作成してマージ |

## プロジェクト設定でのワークフロー定義

`.pi-runner.yaml` でワークフローを直接定義することもできます：

```yaml
# .pi-runner.yaml
workflow:
  name: custom
  description: プロジェクト固有のワークフロー
  steps:
    - plan
    - implement
    - review
    - merge
```

## 関連ドキュメント

- [設定ファイル](./configuration.md) - ワークフロー設定の詳細
- [Hook機能](./hooks.md) - ワークフローイベントでのカスタム処理
- [仕様書](./SPECIFICATION.md) - 完全な技術仕様
