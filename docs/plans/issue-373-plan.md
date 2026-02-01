# Issue #373 実装計画

## 概要

AGENTS.md のディレクトリ構造セクションに、欠落している `lib/cleanup-orphans.sh` と `lib/cleanup-plans.sh` の記載を追加する。

## 影響範囲

- `AGENTS.md` - ディレクトリ構造セクションの lib/ 部分のみ

## 実装ステップ

1. AGENTS.md の lib/ セクションに以下を追加（アルファベット順で agent.sh の後、config.sh の前）:
   - `cleanup-orphans.sh  # 孤立ステータスクリーンアップ`
   - `cleanup-plans.sh    # 計画書クリーンアップ`

## テスト方針

- ドキュメント変更のみのため、テストは不要
- Markdown構文が正しいことを確認

## リスクと対策

- リスク: なし（ドキュメント変更のみ）
