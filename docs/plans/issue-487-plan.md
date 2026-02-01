# Issue #487 Implementation Plan

## 概要
複数のIssueを依存関係（blockedBy）を解析してトポロジカルソートし、正しい順序で自動実行する `scripts/run-batch.sh` を追加します。

## 影響範囲
- 新規: `lib/dependency.sh` - 依存関係解析・レイヤー計算
- 新規: `scripts/run-batch.sh` - メインスクリプト
- 新規: `test/lib/dependency.bats` - ユニットテスト
- 新規: `test/scripts/run-batch.bats` - 統合テスト

## 実装ステップ

### Step 1: lib/dependency.sh の作成
- `get_issue_blockers_numbers()`: Issueのブロッカー番号一覧を取得（スペース区切り）
- `build_dependency_graph()`: 複数Issueの依存関係グラフを構築
- `detect_cycles()`: 循環依存を検出
- `compute_layers()`: レイヤー計算（深さベース）
- `format_layers_for_display()`: レイヤー表示用フォーマット

### Step 2: scripts/run-batch.sh の作成
- 引数パース（Issue番号、オプション）
- 依存関係解析
- レイヤー計算
- レイヤーごとの実行（並列/順次）
- 完了待機（wait-for-sessions.sh利用）
- 結果サマリー

### Step 3: テスト作成
- dependency.bats: レイヤー計算、循環検出のテスト
- run-batch.bats: 統合テスト（モック使用）

## テスト方針
- ユニットテスト: 依存関係解析、レイヤー計算の各関数
- 統合テスト: オプション解析、実行フロー（モック化）
- エッジケース: 循環依存、単一Issue、依存関係なし

## リスクと対策
1. **循環依存**: `detect_cycles()` で事前検出し、エラー終了（exit code 2）
2. **tsort未インストール**: 純粋なBash実装のフォールバック
3. **並列実行制限**: 既存の `check_concurrent_limit()` を活用
4. **APIレート制限**: 依存関係取得をバッチ化（キャッシュ検討）

## 終了コード
- 0: 全Issue成功
- 1: 一部Issue失敗
- 2: 循環依存検出
- 3: 引数エラー
