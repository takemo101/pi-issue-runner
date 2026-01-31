# Issue #212 実装計画

## 概要

`test/lib/github.bats` で呼び出されている `detect_dangerous_patterns` 関数を、
実際の関数名 `has_dangerous_patterns` に修正する。

## 問題の詳細

### 現状
- `test/lib/github.bats:170-194` で `detect_dangerous_patterns` を呼び出している
- `lib/github.sh` には `has_dangerous_patterns` という関数が定義されている
- 存在しない関数を呼び出しているため、Bats警告 (BW01) が発生
- テストは実質的に何もテストしていない

### 追加の問題: 戻り値の期待値が逆

`has_dangerous_patterns` の実装:
- 危険パターンあり → `return 0` (bash的にtrue)
- 安全 → `return 1` (bash的にfalse)

しかし、テストの期待値:
- 危険パターンあり → `status -eq 1` ← **間違い**
- 安全 → `status -eq 0` ← **間違い**

## 影響範囲

- `test/lib/github.bats` のみ

## 実装ステップ

1. 関数名の修正
   - `detect_dangerous_patterns` → `has_dangerous_patterns`
   - 4箇所（テスト名とrun文）

2. 期待値の修正
   - 危険パターン検出テスト: `status -eq 1` → `status -eq 0`
   - 安全テキストテスト: `status -eq 0` → `status -eq 1`

3. テスト実行で確認

## テスト方針

```bash
# 修正対象のテストのみ実行
bats test/lib/github.bats

# 全テスト実行
./scripts/test.sh
```

## リスクと対策

- **リスク**: 無し（テストコードの修正のみ）
- **対策**: 修正後にテストが警告なしで通過することを確認
