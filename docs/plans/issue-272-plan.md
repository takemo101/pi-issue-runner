# Issue #272 実装計画書

## 概要

`lib/` および `test/lib/` ディレクトリに存在する `template.sh`, `yaml.sh`, `template.bats`, `yaml.bats` が README.md と AGENTS.md のディレクトリ構造ツリーに記載されていない問題を修正する。

## 影響範囲

- `README.md` - ディレクトリ構造セクションとテスト構造セクション
- `AGENTS.md` - ディレクトリ構造セクション

## 実装ステップ

1. README.md の lib/ セクションに `template.sh` と `yaml.sh` を追加
2. README.md の test/lib/ セクションに `template.bats` と `yaml.bats` を追加
3. AGENTS.md の lib/ セクションに `template.sh` と `yaml.sh` を追加
4. AGENTS.md の test/lib/ セクションに `template.bats` と `yaml.bats` を追加

## テスト方針

- ドキュメント変更のため、テストコードの変更は不要
- 変更後のファイル構造とドキュメントの整合性を確認

## リスクと対策

- **リスク**: 他にも記載漏れがある可能性
- **対策**: 実際のファイル構造と比較して確認済み

## 作業時間見積もり

約15分
