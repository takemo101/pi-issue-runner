# Implementation Plan for Issue #514

## 概要
README.md と install.sh で `pi-force-complete` コマンドが重複して定義されている問題を修正します。

## 影響範囲
- `README.md` - コマンド一覧表から重複行を削除
- `install.sh` - COMMANDS変数から重複マッピングを削除

## 実装ステップ

### 1. README.md の修正
- 行68-70付近（`pi-watch` と `pi-init` の間）にある重複した `pi-force-complete` の行を削除
- 正確な位置: `| \`pi-force-complete\` | セッション強制完了 |` （2回目の出現）

### 2. install.sh の修正
- COMMANDS変数内の `pi-force-complete:scripts/force-complete.sh` の重複エントリを削除
- 正確な位置: `pi-init:scripts/init.sh` の次の行

## テスト方針
- grep で各ファイル内の `pi-force-complete` の出現回数を確認
- 期待値: 各ファイルで1回のみ出現

## リスクと対策
- リスク: 誤って別の行を削除する
- 対策: 修正前に該当行を確認し、正確に重複行のみを削除する

## 検証手順
```bash
grep "pi-force-complete" README.md | wc -l
grep "pi-force-complete" install.sh | wc -l
```
両方とも結果が1であることを確認する。
