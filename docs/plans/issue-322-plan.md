# Issue #322 実装計画書

## 概要

`scripts/cleanup.sh`の`cleanup_old_plans()`関数内で、未使用の変数`delete_count`を削除する。

## 影響範囲

- **ファイル**: `scripts/cleanup.sh`
- **関数**: `cleanup_old_plans()`
- **行**: 106行目

## 問題の詳細

```bash
local delete_count=$((total_count - keep_count))
```

この変数は計算されているが、その後の処理では`deleted`変数が使用されており、`delete_count`は一度も参照されていない。

## 実装ステップ

1. 106行目の`local delete_count=$((total_count - keep_count))`を削除する

## テスト方針

1. `./scripts/test.sh --shellcheck` を実行してSC2034警告が解消されることを確認
2. `./scripts/test.sh scripts` を実行して`cleanup.sh`のテストがパスすることを確認

## リスクと対策

- **リスク**: なし（未使用変数の削除のみ）
- **機能への影響**: なし（実際の削除カウントは`deleted`変数で追跡されている）
