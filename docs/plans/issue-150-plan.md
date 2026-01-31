# Issue #150 実装計画

## 概要

#146で追加された新機能（improve.sh, wait-for-sessions.sh, notify.sh, status.sh）のドキュメントをSKILL.mdとAGENTS.mdに追加する。

## 影響範囲

- `SKILL.md` - クイックリファレンスに継続的改善セクション追加
- `AGENTS.md` - ディレクトリ構造と開発コマンド更新

## 実装ステップ

### 1. SKILL.md更新
- クイックリファレンスに「継続的改善」セクションを追加
- `scripts/improve.sh` の使用方法を記載
- `scripts/wait-for-sessions.sh` の使用方法を記載

### 2. AGENTS.md更新
- ディレクトリ構造に以下を追加:
  - `scripts/improve.sh`
  - `scripts/wait-for-sessions.sh`
  - `lib/notify.sh`
  - `lib/status.sh`
- 開発コマンドに継続的改善と複数セッション待機のコマンドを追加

## テスト方針

- ドキュメントの変更のみなので、構文チェックは不要
- 目視確認で正しく追加されていることを確認

## リスクと対策

- リスク: マークダウンのフォーマット崩れ
- 対策: 既存のスタイルに合わせて追加
