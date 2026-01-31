# Issue #329 実装計画

## 概要

ワークフロー関連ライブラリのテストファイルを作成し、テストカバレッジを向上させます。

## 影響範囲

### 新規作成ファイル
- `test/lib/workflow-finder.bats`
- `test/lib/workflow-loader.bats`
- `test/lib/workflow-prompt.bats`

### 関連するライブラリ
- `lib/workflow-finder.sh` - ワークフロー・エージェントファイル検索
- `lib/workflow-loader.sh` - ワークフロー読み込み・解析
- `lib/workflow-prompt.sh` - ワークフロープロンプト生成

## 実装ステップ

### 1. workflow-finder.bats の作成
テスト対象関数:
- `find_workflow_file()` - ワークフローファイル検索（優先順位順）
- `find_agent_file()` - エージェントファイル検索

テストケース:
- `.pi-runner.yaml` が存在する場合の検索
- `.pi/workflow.yaml` が存在する場合
- `workflows/{name}.yaml` が存在する場合
- ビルトインへのフォールバック
- エージェントファイルの検索順序

### 2. workflow-loader.bats の作成
テスト対象関数:
- `get_workflow_steps()` - ワークフローからステップ一覧を取得
- `get_agent_prompt()` - エージェントプロンプトを取得

テストケース:
- ビルトインワークフロー（default, simple）のステップ取得
- YAMLファイルからのステップ解析
- `.pi-runner.yaml` 形式からの読み込み
- ビルトインエージェントプロンプトの取得
- カスタムエージェントファイルからの読み込み
- テンプレート変数の展開

### 3. workflow-prompt.bats の作成
テスト対象関数:
- `generate_workflow_prompt()` - ワークフロープロンプトを生成
- `write_workflow_prompt()` - ワークフロープロンプトをファイルに書き出し

テストケース:
- プロンプトヘッダーの生成
- 各ステップのプロンプト生成
- フッターの生成（エラーマーカー、完了マーカー）
- ファイルへの書き出し

## テスト方針

- 既存の `test/lib/*.bats` のパターンに従う
- `test_helper.bash` のsetup/teardownを利用
- 一時ディレクトリにテスト用ファイルを作成
- `yaml.sh` を依存としてテスト

## リスクと対策

| リスク | 対策 |
|--------|------|
| 依存ライブラリの不足 | 各テストファイルで必要なライブラリをsource |
| yqの有無 | yqがない場合はフォールバックパーサーでテスト |
| テストの重複 | workflow.batsとの重複を避け、個別ライブラリの単体テストに集中 |

## 見積もり時間

| タスク | 時間 |
|--------|------|
| workflow-finder.bats | 30分 |
| workflow-loader.bats | 40分 |
| workflow-prompt.bats | 30分 |
| テスト実行・修正 | 20分 |
| **合計** | **2時間** |
