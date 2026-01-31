# Issue #295 実装計画書

## 概要

AGENTS.md のディレクトリ構造セクションに `lib/hooks.sh` と `test/lib/hooks.bats` の記載が欠落しているため、これを追加する。

## 問題の分析

### 発見した不整合

1. **lib/hooks.sh が欠落**: lib/ セクションに `hooks.sh` が記載されていない
2. **test/lib/hooks.bats が欠落**: test/lib/ セクションにも `hooks.bats` が記載されていない

### 影響範囲

- `AGENTS.md` のみ

## 実装ステップ

1. AGENTS.md の lib/ セクションに `hooks.sh` を追加（アルファベット順: github.sh の後）
2. AGENTS.md の test/lib/ セクションに `hooks.bats` を追加（アルファベット順: github.bats の後）

## テスト方針

- ドキュメント変更のため、テストファイルの更新は不要
- 変更後に diff で正しく追加されたことを確認

## リスクと対策

- リスク: 特になし（ドキュメント修正のみ）
- 対策: 変更前に現在のファイル構造を確認済み

## 完了条件

- [x] AGENTS.md の lib/ セクションに `hooks.sh` が追加される
- [x] AGENTS.md の test/lib/ セクションに `hooks.bats` が追加される
