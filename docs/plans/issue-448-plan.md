# Issue #448 Implementation Plan

## 概要
README.md のグローバルインストールセクションにあるコマンド一覧表に `pi-force-complete` コマンドが記載されていません。また、install.sh にも `pi-force-complete` のインストール定義がありません。

## 影響範囲
- `README.md` - コマンド表の更新
- `install.sh` - COMMANDS変数に `pi-force-complete` を追加

## 実装ステップ
1. install.sh の COMMANDS 変数に `pi-force-complete:scripts/force-complete.sh` を追加
2. README.md のコマンド表に `pi-force-complete` の行を追加（pi-cleanup と pi-improve の間に配置）

## テスト方針
- README.md の grep で `pi-force-complete` が含まれていることを確認
- install.sh の grep で `force-complete` が含まれていることを確認

## リスクと対策
- リスク: なし（ドキュメントとインストールスクリプトの更新のみ）
- 対策: 特になし
