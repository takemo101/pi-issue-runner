# Issue #562 Implementation Plan

## 概要

`scripts/run-batch.sh` (507行) を500行以下に収めるため、バッチ処理のコア機能を `lib/batch.sh` として分離するリファクタリング。

## 影響範囲

### 変更対象ファイル
- `scripts/run-batch.sh` - 507行 → 約250行以下に削減
- `lib/batch.sh` (新規作成) - 分離した関数を配置

### テスト対象
- `test/scripts/run-batch.bats` - 既存テストはそのままパスすべき
- `test/lib/batch.bats` (新規) - lib/batch.sh のユニットテスト

## 実装ステップ

### Step 1: 関数の分類

#### scripts/run-batch.sh に残す要素:
- `usage()` - スクリプト固有のヘルプ表示
- グローバル変数定義 (DRY_RUN, SEQUENTIAL, TIMEOUT等)
- `parse_arguments()` - 引数パース（グローバル変数設定）
- `main()` - メインエントリーポイント
- ライブラリ読み込み

#### lib/batch.sh に移動する関数:
- `execute_issue()` - Issueの同期実行
- `execute_issue_async()` - Issueの非同期実行  
- `wait_for_layer_completion()` - レイヤー完了待機
- `execute_layer_sequential()` - レイヤーの順次実行
- `execute_layer_parallel()` - レイヤーの並列実行
- `process_layer()` - レイヤー処理
- `show_execution_plan()` - 実行計画表示
- `show_summary_and_exit()` - 結果サマリー表示

### Step 2: lib/batch.sh の作成

- 既存のライブラリパターンに従う (set -euo pipefail, _BATCH_LIB_DIR 等)
- 必要なライブラリを source (log.sh, status.sh)
- グローバル変数への依存を明示（ドキュメント化）

### Step 3: scripts/run-batch.sh の修正

- `lib/batch.sh` を source
- 移動した関数を削除
- 関数呼び出しを維持

### Step 4: テスト

- 既存テスト実行: `bats test/scripts/run-batch.bats`
- 新規テスト作成: `test/lib/batch.bats`
- 行数確認: `wc -l scripts/run-batch.sh`

## テスト方針

### 既存テスト
- 既存の `test/scripts/run-batch.bats` は変更なしで全てパスすべき
- 外部インターフェース（コマンドライン引数、終了コード、出力形式）を維持

### 新規テスト (test/lib/batch.bats)
- `execute_issue()` のテスト
- `wait_for_layer_completion()` のモックテスト
- `show_execution_plan()` の出力テスト
- `show_summary_and_exit()` の終了コードテスト

## リスクと対策

| リスク | 対策 |
|--------|------|
| グローバル変数の依存関係 | 明確にドキュメント化、set -euo pipefail で未定義変数を検出 |
| 関数の呼び出し元変更 | 関数名・シグネチャを維持、純粋な移動のみ |
| テストの破壊 | 既存テストを事前に実行、変更後に再実行して比較 |
| パスの解決 | SCRIPT_DIR の取得方法を統一 |

## 完了条件

- [x] `scripts/run-batch.sh` が500行以下になっている (263行)
- [x] `lib/batch.sh` が作成され、分割した関数が含まれている (282行)
- [x] 既存テスト `test/scripts/run-batch.bats` が全てパス (52テスト)
- [x] 新規テスト `test/lib/batch.bats` が作成され、主要関数がテストされている (35テスト)
- [x] ShellCheck で警告が出ていない
