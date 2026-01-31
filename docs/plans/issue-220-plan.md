# Issue #220 実装計画書

## 概要

`test/lib/github.bats` のテストで参照している関数名 `detect_dangerous_patterns` を、`lib/github.sh` で実際に定義されている関数名 `has_dangerous_patterns` に修正する。

## 問題分析

### 現状
- `lib/github.sh:120` には `has_dangerous_patterns()` が定義されている
- `test/lib/github.bats:170-194` では `detect_dangerous_patterns` を呼び出している
- 関数名が不一致のため、テスト実行時にBW01警告が発生し、実際の関数がテストされていない

### 影響箇所
| ファイル | 行番号 | 現在の関数名 | 修正後 |
|---------|-------|-------------|--------|
| test/lib/github.bats | 173 | detect_dangerous_patterns | has_dangerous_patterns |
| test/lib/github.bats | 180 | detect_dangerous_patterns | has_dangerous_patterns |
| test/lib/github.bats | 187 | detect_dangerous_patterns | has_dangerous_patterns |
| test/lib/github.bats | 194 | detect_dangerous_patterns | has_dangerous_patterns |

## 実装ステップ

1. `test/lib/github.bats` の4箇所の関数名を修正
2. テスト実行して全テストがパスすることを確認
3. BW01警告が出ないことを確認

## テスト方針

```bash
./scripts/test.sh lib
```

## リスクと対策

- **リスク**: なし（単純な関数名の修正のみ）
- **対策**: テスト実行による動作確認

## 見積もり

10分
