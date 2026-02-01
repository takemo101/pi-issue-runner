# Implementation Plan: Issue #366

## 概要

AGENTS.md のディレクトリ構造セクションに `lib/cleanup-orphans.sh` と `lib/cleanup-plans.sh` を追加する。

## 影響範囲

- `AGENTS.md` - ドキュメントのみの変更

## 現状分析

### 存在するファイル
- ✅ `lib/cleanup-orphans.sh` - 孤立ステータスファイルのクリーンアップ
- ✅ `lib/cleanup-plans.sh` - 計画書のクリーンアップ

### テストファイル
- ❌ `test/lib/cleanup-orphans.bats` - 存在しない
- ❌ `test/lib/cleanup-plans.bats` - 存在しない

## 実装ステップ

1. AGENTS.md の `lib/` セクション（38-57行目付近）に cleanup ファイルを追加
   - `cleanup-orphans.sh` を追加
   - `cleanup-plans.sh` を追加
   - アルファベット順を維持

2. AGENTS.md の `test/lib/` セクションへの更新
   - 現時点ではテストファイルが存在しないため、追加しない
   - Issue説明にある「テスト作成後」の条件に従う

## テスト方針

- ドキュメントのみの変更のため、特別なテストは不要
- 既存テストが引き続きパスすることを確認

## リスクと対策

- リスク: なし（ドキュメントのみの変更）
- 対策: 変更後にファイル構造との整合性を確認

## 完了条件

- [x] Issueの要件を完全に理解した
- [x] 関連するコードを調査した
- [x] 実装計画書を作成した
- [x] 計画書をファイルに保存した
