# Implementation Plan: Issue #354

## 概要

AGENTS.md および README.md の lib/ ディレクトリ構造セクションに、欠落している2つのファイル（`cleanup-orphans.sh` と `cleanup-plans.sh`）の記載を追加する。

## 影響範囲

- `AGENTS.md` - ディレクトリ構造セクション（35行目付近）
- `README.md` - ディレクトリ構造セクション（362行目付近）

## 実装ステップ

### 1. AGENTS.md の修正

lib/ セクション内で、`agent.sh` の後、`config.sh` の前に以下の2行を追加:
```
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
```

### 2. README.md の修正

lib/ セクション内で、`agent.sh` の後、`config.sh` の前に以下の2行を追加:
```
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
```

## テスト方針

- ドキュメントの変更のみのため、単体テストは不要
- 視覚的な確認でフォーマットの一貫性を確認

## リスクと対策

- **リスク**: 他のドキュメントにも同様の構造がある可能性
- **対策**: grep で確認済み、AGENTS.md と README.md のみが対象

## 見積もり

約15分
