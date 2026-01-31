# Issue #343 実装計画書

## refactor: scripts/cleanup.sh の分割検討

## 1. 概要

`scripts/cleanup.sh` (425行) を分割し、保守性を向上させます。

### 方針決定: **A案採用**

現在のファイルサイズ (425行) は推奨の300-400行を超えており、
独立した機能が複数存在するため、lib/への分離が適切と判断します。

## 2. 影響範囲

### 変更対象ファイル

| ファイル | 変更内容 |
|----------|----------|
| `scripts/cleanup.sh` | 関数をlib/に移動し、sourceで呼び出し |
| `lib/cleanup-plans.sh` | **新規作成**: 計画書関連のクリーンアップ関数 |
| `lib/cleanup-orphans.sh` | **新規作成**: 孤立ファイルのクリーンアップ関数 |

### 機能の分離

```
lib/
├── cleanup-plans.sh      # cleanup_old_plans(), cleanup_closed_issue_plans()
└── cleanup-orphans.sh    # cleanup_orphaned_statuses()

scripts/
└── cleanup.sh            # メインエントリーポイント + usage() + main()
```

## 3. 実装ステップ

### Step 1: lib/cleanup-plans.sh の作成
- `cleanup_old_plans()` 関数を移動 (~70行)
- `cleanup_closed_issue_plans()` 関数を移動 (~57行)
- 必要な依存関係(config.sh, log.sh)をsource

### Step 2: lib/cleanup-orphans.sh の作成
- `cleanup_orphaned_statuses()` 関数を移動 (~34行)
- 必要な依存関係(status.sh, log.sh)をsource

### Step 3: scripts/cleanup.sh の更新
- 新しいlib/ファイルをsource
- 関数定義を削除（lib/から呼び出し）
- usage()とmain()のみを維持

### Step 4: テスト実行
- `./scripts/test.sh scripts` で統合テスト実行
- ShellCheck で静的解析

## 4. 予想されるファイルサイズ

| ファイル | 予想行数 |
|----------|----------|
| `scripts/cleanup.sh` | ~260行 (usage + main) |
| `lib/cleanup-plans.sh` | ~150行 |
| `lib/cleanup-orphans.sh` | ~60行 |

## 5. テスト方針

### 既存テストの確認
- `test/scripts/cleanup.bats` (247行) の全テストがパスすること
- 新しいlib/に対するユニットテストは既存テストでカバーされるため追加不要

### 手動テスト
```bash
# ヘルプ
./scripts/cleanup.sh --help

# orphansクリーンアップ
./scripts/cleanup.sh --orphans --dry-run

# plans ローテーション
./scripts/cleanup.sh --rotate-plans --dry-run

# 全クリーンアップ
./scripts/cleanup.sh --all --dry-run
```

## 6. リスクと対策

| リスク | 対策 |
|--------|------|
| source順序の問題 | 依存関係を明示的にソースし、ガード処理を追加 |
| 関数名の衝突 | 既存の命名規則を維持（cleanup_*） |
| テスト失敗 | 全テスト合格を確認してからコミット |

## 7. 受け入れ条件

- [x] 方針を決定（A案）
- [x] 分割後も全テストが合格する（641 tests, 0 failures）
- [x] 各ファイルが300行以下
  - scripts/cleanup.sh: 233行
  - lib/cleanup-plans.sh: 171行
  - lib/cleanup-orphans.sh: 65行
- [x] ShellCheckで警告なし
