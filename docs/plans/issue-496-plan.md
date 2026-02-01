# Issue #496 実装計画

## 概要

`install.sh` の COMMANDS 定義で `pi-force-complete` が2回定義されている重複エントリを削除する。

## 影響範囲

- `install.sh` - 1行削除（行143の重複エントリ）

## 実装ステップ

1. `install.sh` の COMMANDS 変数から重複エントリを削除
   - 行143: `pi-force-complete:scripts/force-complete.sh` を削除
2. 変更を確認
   - `grep -c "pi-force-complete" install.sh` が 1 を返すことを確認
3. テスト実行
   - インストールスクリプトの構文チェック
4. コミット作成

## テスト方針

- grepコマンドで重複が解消されたことを確認
- ShellCheckで構文エラーがないことを確認

## リスクと対策

- **リスク**: 誤って行138のエントリを削除する
- **対策**: 行番号を確認し、行143のみを削除

## 完了条件

- [ ] 行143の重複エントリを削除
- [ ] `grep -c "pi-force-complete" install.sh` が 1 を返す
- [ ] インストールスクリプトが正常に動作する
