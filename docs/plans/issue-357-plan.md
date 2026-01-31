# Issue #357 実装計画書

## 概要

`install.sh` の未使用変数 `OPTIONAL_DEPS` を削除し、ShellCheck警告を解消する。

## 問題

- `install.sh:20` で `OPTIONAL_DEPS=""` が定義されているが使用されていない
- ShellCheck SC2034 警告が発生している

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `install.sh` | 未使用変数 `OPTIONAL_DEPS` とコメントを削除 |

## 実装ステップ

1. `install.sh` から `OPTIONAL_DEPS=""` 行とそのコメントを削除
2. ShellCheck でエラーがないことを確認
3. テストを実行して既存機能に影響がないことを確認

## テスト方針

1. `shellcheck -x install.sh` でSC2034警告が解消されていることを確認
2. `./scripts/test.sh --shellcheck` でプロジェクト全体のShellCheck確認
3. `./install.sh --help` で基本動作確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 将来的にOPTIONAL_DEPSが必要になる可能性 | 必要になった時点で再追加すれば良い。YAGNI原則に従う |
| 削除漏れ | ShellCheckで再確認 |

## 見積もり

10分以内
