# Issue #483 Implementation Plan

test: lib/github.shの依存関係取得関数のテストを追加

## 概要

`lib/github.sh` の依存関係取得関数 `get_issue_blockers` と `check_issue_blocked` のテストを `test/lib/github.bats` に追加します。

## 影響範囲

- `test/lib/github.bats` - テストケースの追加

## 実装ステップ

1. **現状調査**: 既存の `lib/github.sh` と `test/lib/github.bats` を確認
2. **テスト実装**: 以下のテストケースを追加
   - `get_issue_blockers` のテスト（3ケース）
   - `check_issue_blocked` のテスト（4ケース）
3. **テスト実行**: 全テストがパスすることを確認
4. **コミット**: 変更をコミット

## テスト方針

### get_issue_blockers
- `gh api graphql` モックを使用して GraphQL API レスポンスをシミュレート
- 空のブロッカーリスト、複数ブロッカー、APIエラーの3パターンをテスト

### check_issue_blocked
- `get_issue_blockers` をモックして依存関数の動作をシミュレート
- ブロッカーなし、全てCLOSED、OPENあり、取得失敗の4パターンをテスト

## 確認結果

実装時に確認したところ、既に必要なテストケースがすべて実装済みでした：

- `get_issue_blockers` 関数のテスト: 5ケース（test 37-41）
- `check_issue_blocked` 関数のテスト: 5ケース（test 42-46）

全46テストがパスすることを確認済みです。

## リスクと対策

- 既存テストとの競合: なし（独立したテストケース）
- モックの複雑性: `test_helper.bash` の既存パターンに従って実装
