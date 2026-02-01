# Issue #402 実装計画

## 概要

`lib/ci-fix.sh`（524行）を単一責任原則に従って複数のモジュールに分割します。

## 現状分析

### ファイル構成（現在）
- `lib/ci-fix.sh`: 524行
  - コメント・空行除く実質コード: 約361行
  - 責務が7つ混在

### 責務の分類
1. **CI状態監視** - CI完了待機、PRチェック状態取得
2. **失敗分析** - 失敗ログ取得、失敗タイプ分類
3. **自動修正実行** - lint/format修正、ローカル検証
4. **リトライ管理** - リトライ回数の追跡・管理
5. **エスカレーション** - Draft化、コメント投稿
6. **メイン処理** - 統合ハンドラ

## 分割案

### 新しいファイル構成

| ファイル | 行数（推定） | 責務 |
|---------|------------|------|
| `lib/ci-monitor.sh` | ~100行 | CI状態監視 |
| `lib/ci-classifier.sh` | ~80行 | 失敗タイプ分類・ログ取得 |
| `lib/ci-retry.sh` | ~90行 | リトライ管理 |
| `lib/ci-fix.sh` | ~200行 | 自動修正・エスカレーション（コア） |

### 総行数
- 分割前: 524行
- 分割後: ~470行（ヘッダー・ソース文追加により増加）

## 実装ステップ

### Step 1: 定数の共有化
- 失敗タイプ定数（FAILURE_TYPE_*）をどのファイルに置くか決定
- 全モジュールで必要な定数は ci-fix.sh に残す

### Step 2: 新規ファイル作成（責務ごと）

#### lib/ci-monitor.sh
```bash
# 関数
- wait_for_ci_completion()
- get_pr_checks_status()

# 定数
- CI_POLL_INTERVAL
- CI_TIMEOUT
```

#### lib/ci-classifier.sh
```bash
# 関数
- get_failed_ci_logs()
- classify_ci_failure()

# 定数
- FAILURE_TYPE_* (export)
```

#### lib/ci-retry.sh
```bash
# 関数
- get_retry_state_file()
- get_retry_count()
- increment_retry_count()
- reset_retry_count()
- should_continue_retry()

# 定数
- MAX_RETRY_COUNT
```

#### lib/ci-fix.sh（更新）
```bash
# ソース
source "$__CI_FIX_LIB_DIR/ci-monitor.sh"
source "$__CI_FIX_LIB_DIR/ci-classifier.sh"
source "$__CI_FIX_LIB_DIR/ci-retry.sh"

# 関数
- try_auto_fix()
- try_fix_lint()
- try_fix_format()
- run_local_validation()
- escalate_to_manual()
- mark_pr_as_draft()
- add_pr_comment()
- handle_ci_failure()
```

### Step 3: テストの分割・作成

#### test/lib/ci-monitor.bats
- `wait_for_ci_completion` のテスト（モック使用）
- `get_pr_checks_status` のテスト

#### test/lib/ci-classifier.bats
- `classify_ci_failure` のテスト（既存テスト移行）
- `get_failed_ci_logs` のテスト

#### test/lib/ci-retry.bats
- リトライ管理関数のテスト（既存テスト移行）

#### test/lib/ci-fix.bats（更新）
- 自動修正関連のテストのみ残す
- 削除した関数のテストを削除

### Step 4: 統合テスト
- 既存の ci-fix.bats で後方互換性を確認
- 全テスト実行

## 影響範囲

### 変更対象ファイル
1. `lib/ci-fix.sh` - 大幅に削減・リファクタリング
2. `lib/ci-monitor.sh` - 新規作成
3. `lib/ci-classifier.sh` - 新規作成
4. `lib/ci-retry.sh` - 新規作成

### テストファイル
1. `test/lib/ci-fix.bats` - 更新（不要テスト削除）
2. `test/lib/ci-monitor.bats` - 新規作成
3. `test/lib/ci-classifier.bats` - 新規作成
4. `test/lib/ci-retry.bats` - 新規作成

### 影響を受ける可能性のあるファイル
- `scripts/*.sh` - `ci-fix.sh` をsourceしている場合
- 調査結果: `scripts/` 内で ci-fix.sh を直接sourceしているファイルはなし

## 後方互換性

### 維持するインターフェース
`lib/ci-fix.sh` をsourceすることで、これまで通り全ての関数・定数が利用可能。

```bash
# これまで通り動作
source "$PROJECT_ROOT/lib/ci-fix.sh"
classify_ci_failure "$log"  # ci-classifier.sh の関数
get_retry_count 123        # ci-retry.sh の関数
```

### 注意点
- 個別モジュールのみをsourceする場合は、依存関係に注意
- `ci-classifier.sh` は `log.sh` に依存
- `ci-monitor.sh` は `log.sh`, `github.sh` に依存

## テスト方針

### 単体テスト
- 各モジュールごとに独立したテストを作成
- モックを使用して外部依存（gh, cargo）を分離

### 統合テスト
- `ci-fix.sh` をsourceした際の動作確認
- 関数の相互呼び出しが正しく動作することを確認

### 回帰テスト
- 既存の ci-fix.bats から関連テストを移行
- 削除した関数のテストは新モジュールに移動

## リスクと対策

| リスク | 対策 |
|-------|------|
| 循環import | 依存関係を整理し、共通定数はci-fix.shに集約 |
| 後方互換性破壊 | ci-fix.shが全モジュールをsourceすることで維持 |
| テスト失敗 | 移行前に既存テストを全てパスさせてから実施 |
| 関数重複 | 分割時に1つの関数が複数ファイルにまたがらないように注意 |

## 実装後の行数見積もり

| ファイル | 推定行数 |
|---------|---------|
| lib/ci-monitor.sh | ~100行 |
| lib/ci-classifier.sh | ~80行 |
| lib/ci-retry.sh | ~90行 |
| lib/ci-fix.sh | ~160行（コア機能のみ） |
| **合計** | **~430行** |

※ ヘッダーコメント・ソース文による増加を考慮
