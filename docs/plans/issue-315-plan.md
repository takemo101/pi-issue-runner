# Issue #315 実装計画書

## refactor: lib/workflow.shを機能ごとに分割（424行→複数ファイル）

## 概要

`lib/workflow.sh`（424行）を単一責任原則に従って複数ファイルに分割する。

## 影響範囲

### 変更対象ファイル
- `lib/workflow.sh` - 分割元（リファクタリング後は200行以下）
- 新規: `lib/workflow-finder.sh` - ファイル検索機能
- 新規: `lib/workflow-loader.sh` - 読み込み・解析機能

### 依存関係
- `scripts/run.sh` - `lib/workflow.sh` をsource
  - 使用関数: `list_available_workflows`, `write_workflow_prompt`
- `test/lib/workflow.bats` - テストファイル

### 後方互換性
- `lib/workflow.sh` を source することで、すべての機能が引き続き利用可能
- 外部インターフェースは変更なし

## 実装ステップ

### Step 1: `lib/workflow-finder.sh` の作成
ファイル検索に関する関数を移行:
- `find_workflow_file()` - ワークフローファイル検索
- `find_agent_file()` - エージェントファイル検索

### Step 2: `lib/workflow-loader.sh` の作成
読み込み・解析に関する関数を移行:
- `get_workflow_steps()` - ステップ一覧取得
- `get_agent_prompt()` - エージェントプロンプト取得

### Step 3: `lib/workflow.sh` のリファクタリング
- 新ファイルを source
- 実行・プロンプト生成関数を残す:
  - `parse_step_result()`
  - `run_step()`
  - `run_workflow()`
  - `get_workflow_steps_array()`
  - `list_available_workflows()`
  - `generate_workflow_prompt()`
  - `write_workflow_prompt()`

### Step 4: テスト実行
- `./scripts/test.sh lib` で既存テストがパスすることを確認
- 個別ファイルのテストも追加検討

## 新しいファイル構成

```
lib/
├── workflow.sh           # メインエントリ（~200行）
├── workflow-finder.sh    # ファイル検索（~60行）
├── workflow-loader.sh    # 読み込み・解析（~120行）
...
```

## テスト方針

1. 既存テスト（`test/lib/workflow.bats`）がすべてパス
2. ShellCheck によるリント
3. 手動テスト: `./scripts/run.sh --list-workflows`

## リスクと対策

| リスク | 対策 |
|--------|------|
| 依存関係の循環参照 | 各ファイルの source 順序を明確化 |
| 関数の見落とし | grep で使用箇所を確認 |
| テスト漏れ | 既存テストをそのまま維持 |

## 受け入れ条件

- [x] 各ファイルが200行以下 (72, 118, 128, 141行)
- [x] 既存テスト(`test/lib/workflow.bats`)がすべてパス (480テスト全パス)
- [x] 後方互換性維持（外部からの呼び出しに影響なし）
