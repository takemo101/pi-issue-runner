# Issue #133 実装計画書

## 概要

`watch-session.sh` と自動クリーンアップ機能のドキュメントを追加する。

## 影響範囲

- `README.md` - ディレクトリ構造セクション
- `SKILL.md` - 自動クリーンアップの詳細説明
- `docs/SPECIFICATION.md` - watch-session.shの仕様

## 実装ステップ

### 1. README.md 更新
- ディレクトリ構造に `watch-session.sh` を追加
- 説明: 「セッション監視と自動クリーンアップ」

### 2. SKILL.md 更新
- 自動クリーンアップの詳細説明を追加
- `###TASK_COMPLETE_<issue_number>###` マーカーの説明

### 3. docs/SPECIFICATION.md 更新
- ディレクトリ構造に `watch-session.sh` を追加
- watch-session.sh のCLIコマンド仕様を追加

## テスト方針

- ドキュメントの構文チェック（リンクの有効性など）
- 変更内容のレビュー

## リスクと対策

- リスク: ドキュメントの一貫性が失われる可能性
- 対策: 既存のスタイルに従って記述する

## 推定工数

- README.md: 10行程度
- SKILL.md: 20行程度
- docs/SPECIFICATION.md: 50行程度
- 合計: 約80行
