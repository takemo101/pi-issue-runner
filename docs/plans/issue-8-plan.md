# 実装計画書: Issue #8 - Batsテストの追加

## 概要

Bats (Bash Automated Testing System) を使用したテストを追加し、既存のカスタムテストフレームワークから移行する。

## 現状分析

### 既存のテスト構造
- `test/` ディレクトリに17個のカスタム形式テストファイルが存在
- カスタムアサーション関数 (`assert_equals`, `assert_not_empty` など) を使用
- `test/helpers/mocks.sh` に既にBats用のモック準備（`BATS_TEST_TMPDIR`参照）がある
- `test/fixtures/sample-config.yaml` にテスト用設定ファイルが存在

### 課題
- Batsがインストールされていない（`bats not found`）
- 既存テストはBats形式ではない（`@test` 構文なし）
- AGENTS.mdにはBatsテストを記載しているが、実際は独自形式

## 影響範囲

| ファイル/ディレクトリ | 変更内容 |
|----------------------|----------|
| `test/*.bats` | 新規作成（Bats形式テスト） |
| `test/test_helper.bash` | Bats共通ヘルパー |
| `test/helpers/mocks.sh` | Bats互換に調整 |
| `AGENTS.md` | テスト実行コマンド更新 |
| `README.md` | セットアップ手順追加 |
| `.github/workflows/` | CI設定（オプション） |

## 実装ステップ

### Phase 1: 基盤整備

1. **Batsヘルパーファイル作成**
   - `test/test_helper.bash` - 共通のsetup/teardown、アサーション
   - bats-support, bats-assert プラグインの代替実装

2. **モックシステム更新**
   - `test/helpers/mocks.sh` をBats互換に更新
   - `setup()` / `teardown()` 関数との統合

### Phase 2: Batsテスト作成

以下の優先順でBatsテストを作成：

1. **lib/config.sh のテスト** (`test/lib/config.bats`)
   - デフォルト値
   - 環境変数オーバーライド
   - 設定ファイルパース

2. **lib/github.sh のテスト** (`test/lib/github.bats`)
   - Issue取得
   - ブランチ名生成

3. **scripts/run.sh のテスト** (`test/scripts/run.bats`)
   - ヘルプ表示
   - 引数バリデーション
   - エラーケース

4. **その他の統合テスト**

### Phase 3: ドキュメント更新

1. README.mdにBatsセットアップ手順追加
2. AGENTS.mdのテスト実行コマンド更新

## テスト方針

### Batsテスト構造

```bash
# test/lib/config.bats
#!/usr/bin/env bats

load '../test_helper'

@test "get_config returns default worktree_base_dir" {
    source "$PROJECT_ROOT/lib/config.sh"
    result="$(get_config worktree_base_dir)"
    [ "$result" = ".worktrees" ]
}

@test "environment variable overrides config" {
    export PI_RUNNER_WORKTREE_BASE_DIR="custom"
    source "$PROJECT_ROOT/lib/config.sh"
    run get_config worktree_base_dir
    [ "$output" = "custom" ]
}
```

### テストカバレッジ目標

- ユニットテスト: lib/の各関数
- 統合テスト: scripts/の基本動作
- エッジケース: エラーハンドリング

## リスクと対策

| リスク | 対策 |
|--------|------|
| Batsがインストールされていない環境 | インストール手順をREADMEに明記、brew/apt対応 |
| 既存テストとの互換性 | 既存テストは維持し、段階的に移行 |
| モックの複雑化 | シンプルなモックシステムを維持 |

## 完了条件

- [ ] `test/test_helper.bash` 作成
- [ ] 最低3つのlib/用Batsテスト作成
- [ ] 最低2つのscripts/用Batsテスト作成
- [ ] `bats test/` で全テストがパス
- [ ] ドキュメント更新
