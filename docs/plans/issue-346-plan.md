# Issue #346 実装計画

## 概要

プロジェクトレビューで発見された軽微なドキュメント問題を修正する。

## 影響範囲

- `docs/README.md` - 日付表記の修正
- `docs/plans/` - クローズ済み計画書の削除

## 現状確認

### 1. AGENTS.mdのgithub.bats（P2）
- **状態**: ✅ 既に修正済み
- AGENTS.md 64行目に `github.bats` が既に存在する
- **アクション**: 不要

### 2. docs/README.mdの日付（P3）
- **状態**: ❌ 未修正
- 156行目付近に `2024-01-30` の日付が存在
- **アクション**: `2026-01-26` に修正

### 3. クローズ済み計画書（P3）
- **状態**: ❌ 未削除
- 10件の計画書が存在:
  - issue-315-plan.md
  - issue-316-plan.md
  - issue-320-plan.md
  - issue-322-plan.md
  - issue-323-plan.md
  - issue-324-plan.md
  - issue-328-plan.md
  - issue-330-plan.md
  - issue-334-plan.md
  - issue-337-plan.md
- **アクション**: `./scripts/cleanup.sh --delete-plans` を実行

## 実装ステップ

1. docs/README.mdの日付を修正（2024-01-30 → 2026-01-26）
2. cleanup.sh --delete-plans を実行してクローズ済み計画書を削除
3. テストを実行して確認
4. 変更をコミット

## テスト方針

- テストスイートを実行して既存機能への影響がないことを確認
- ドキュメントの変更なのでユニットテストの追加は不要

## リスクと対策

- **リスク**: 計画書の削除で必要なものを消す可能性
- **対策**: cleanup.shはクローズ済みIssueのみを対象とするため安全

## 見積もり

約10分
