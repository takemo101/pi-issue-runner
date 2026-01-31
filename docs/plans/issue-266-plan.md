# 実装計画: Issue #266 - lib/workflow.shからテンプレート処理を分離する

## 概要

`lib/workflow.sh` からテンプレート処理機能を分離し、新しい `lib/template.sh` ファイルを作成する。これにより単一責任原則に沿った設計になり、コードの保守性が向上する。

## 影響範囲

### 変更するファイル
1. `lib/workflow.sh` - テンプレート関連コードを削除し、`template.sh` をsource
2. `test/lib/workflow.bats` - テンプレート関連テストを削除

### 新規作成するファイル
1. `lib/template.sh` - テンプレート処理機能
2. `test/lib/template.bats` - テンプレートのユニットテスト

## 実装ステップ

### ステップ 1: lib/template.sh の作成
以下を `lib/template.sh` に移動:
- `_BUILTIN_AGENT_PLAN`, `_BUILTIN_AGENT_IMPLEMENT`, `_BUILTIN_AGENT_REVIEW`, `_BUILTIN_AGENT_MERGE` 定数
- `render_template()` 関数

### ステップ 2: lib/workflow.sh の更新
- `lib/template.sh` を source する
- 移動した関数・定数を削除

### ステップ 3: test/lib/template.bats の作成
`test/lib/workflow.bats` から以下のテストを移動:
- `render_template renders issue_number and branch_name`
- `render_template renders step_name and workflow_name`
- `render_template renders worktree_path`
- `render_template replaces empty variable with empty string`
- `render_template renders issue_title`
- `render_template combines issue_number, issue_title, branch_name`

### ステップ 4: test/lib/workflow.bats の更新
- render_template 関連テストを削除

### ステップ 5: テスト実行とShellCheck
- 全テストがパスすることを確認
- ShellCheckがパスすることを確認

## テスト方針

### ユニットテスト
- `template.bats`: render_template の全パターン、ビルトインエージェント定数の確認
- `workflow.bats`: 既存テストが引き続きパスすること（template.sh を source 経由で読み込み）

### 統合テスト
- 既存の `test/scripts/run.bats` が引き続きパスすること

## リスクと対策

| リスク | 対策 |
|--------|------|
| source パスの問題 | `SCRIPT_DIR` を使用した相対パス解決 |
| 循環依存 | template.sh は依存なし（log.sh のみ必要に応じて） |
| テスト漏れ | 全テスト実行で確認 |

## 見積もり

- 実装: 30分
- テスト: 30分
- レビュー・調整: 30分
- 合計: 約1.5時間
