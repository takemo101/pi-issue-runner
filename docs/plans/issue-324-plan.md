# Issue #324 実装計画

## 概要

3つのワークフロー関連ライブラリにユニットテストを追加する：
- `lib/workflow-finder.sh` (72行)
- `lib/workflow-loader.sh` (118行)
- `lib/workflow-prompt.sh` (128行)

## 影響範囲

テストファイルの追加のみ。既存コードへの変更なし。

| 新規作成ファイル | テスト対象 |
|-----------------|-----------|
| `test/lib/workflow-finder.bats` | `lib/workflow-finder.sh` |
| `test/lib/workflow-loader.bats` | `lib/workflow-loader.sh` |
| `test/lib/workflow-prompt.bats` | `lib/workflow-prompt.sh` |

## 実装ステップ

### 1. `test/lib/workflow-finder.bats` の作成

テスト対象関数:
- `find_workflow_file()` - ワークフローファイル検索
- `find_agent_file()` - エージェントファイル検索

テスト項目:
- ビルトインのフォールバック動作
- プロジェクトファイル優先順位（.pi-runner.yaml > .pi/workflow.yaml > workflows/）
- エージェント優先順位（agents/ > .pi/agents/ > builtin）

### 2. `test/lib/workflow-loader.bats` の作成

テスト対象関数:
- `get_workflow_steps()` - ワークフローステップ取得
- `get_agent_prompt()` - エージェントプロンプト取得

テスト項目:
- ビルトインワークフロー（default, simple）
- YAMLワークフローの読み込み
- ビルトインエージェントプロンプト
- カスタムエージェントファイル読み込み
- テンプレート変数展開
- エラー処理

### 3. `test/lib/workflow-prompt.bats` の作成

テスト対象関数:
- `generate_workflow_prompt()` - ワークフロープロンプト生成
- `write_workflow_prompt()` - ファイル出力

テスト項目:
- プロンプトヘッダー生成
- ステップ一覧の出力
- コミットタイプフッター
- エラー/完了マーカーの説明
- ファイル書き出し

## テスト方針

- 既存の `test/lib/workflow.bats`, `test/lib/yaml.bats` のパターンに従う
- `test_helper.bash` の共通機能を活用
- 一時ディレクトリにテスト用YAML/MDファイルを作成
- 各関数のエッジケースもテスト

## リスクと対策

| リスク | 対策 |
|-------|-----|
| 依存関数のロード順序 | workflow.sh経由でロードするか、直接sourceして依存解決 |
| yqの有無 | yqがない環境ではYAMLパース関連テストをスキップ |

## 見積もり

- workflow-finder.bats: 30分
- workflow-loader.bats: 45分
- workflow-prompt.bats: 45分
- テスト実行・修正: 30分
- **合計**: 約2.5時間
