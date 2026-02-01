# Issue #503 実装計画

## 概要
`scripts/run-batch.sh` のグローバルコマンド (`pi-batch`) を `install.sh` に追加し、ドキュメントを更新する。

## 影響範囲
- `install.sh` - コマンドマッピングに `pi-batch` を追加
- `README.md` - コマンド一覧表に `pi-batch` を追加

## 実装ステップ
1. `install.sh` の `COMMANDS` 変数に `pi-batch:scripts/run-batch.sh` を追加
2. `README.md` のコマンド一覧表に `pi-batch` の行を追加

## テスト方針
- `install.sh` の構文チェック
- `run-batch.sh` が存在することを確認
- 変更後のファイルの目視確認

## リスクと対策
- **リスク**: 既存のコマンドリストに重複がある可能性
- **対策**: 実装前に既存リストを確認し、重複があれば合わせて修正

## 備考
- `install.sh` には `pi-force-complete` が2回登録されている重複がある
- `README.md` でも `pi-force-complete` が2回表示されている
- 本Issueでは `pi-batch` の追加のみを行い、重複の修正は別途対応
