# 実装計画書 - Issue #148

## 概要

`docs/SPECIFICATION.md` を実際のコードベースと同期させる。削除済みファイルへの参照を削除し、新しく追加されたスクリプト・ライブラリのドキュメントを追加する。

## 影響範囲

- `docs/SPECIFICATION.md` のみ

## 実装ステップ

### P1: 削除済みファイル参照の削除

1. **ディレクトリ構造セクション（Line 112付近）**
   - `post-session.sh` の行を削除

2. **CLIコマンドセクション（Line 170-183付近）**
   - `post-session.sh` のコマンドドキュメントを削除

### P2: 新規スクリプトのドキュメント追加

1. **ディレクトリ構造セクションに追加**
   - `scripts/improve.sh` - 継続的改善スクリプト
   - `scripts/wait-for-sessions.sh` - 複数セッション完了待機
   - `lib/notify.sh` - 通知機能
   - `lib/status.sh` - ステータスファイル管理

2. **CLIコマンドセクションに追加**
   - `improve.sh` のUsage・Options・Description・Examples
   - `wait-for-sessions.sh` のUsage・Options・Description・Examples

## テスト方針

- ドキュメント変更のため、テストは不要
- Markdownの構文が正しいことを目視確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| 既存ドキュメントの構造を壊す | 変更前後でMarkdownの構造を確認 |
| スクリプトの機能を誤って記載 | 実際のスクリプトのusage()を参照して正確に記載 |

## 見積もり

- P1: 5分
- P2: 15分
- 合計: 20分
