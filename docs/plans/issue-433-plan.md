# 実装計画: Issue #433

## 概要

テストと実装の不一致を修正します。
- テストは `.pi-runner.yml` を期待している
- 実装は `.pi-runner.yaml` を追加している

実装に合わせてテストを修正します。

## 影響範囲

- `test/scripts/init.bats` (line 79)

## 実装ステップ

1. テスト名を修正: `.pi-runner.yml` → `.pi-runner.yaml`
2. grepパターンを修正: `\.pi-runner\.yml` → `\.pi-runner\.yaml`

## テスト方針

- 修正後のテストを実行して確認

## リスクと対策

- リスクなし - 単純なテスト修正
