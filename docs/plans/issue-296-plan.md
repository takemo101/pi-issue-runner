# Issue #296 実装計画

## 概要

AGENTS.md と README.md のディレクトリ構造セクションに `test/lib/hooks.bats` の記載が欠落しているため追加する。また、AGENTS.md では `lib/hooks.sh` の記載も欠落していることを確認。

## 影響範囲

### 変更ファイル
1. **AGENTS.md**
   - `lib/` セクション: `hooks.sh` を追加（github.sh と log.sh の間）
   - `test/lib/` セクション: `hooks.bats` を追加（github.bats と log.bats の間）
   
2. **README.md**
   - `test/lib/` セクション: `hooks.bats` を追加（github.bats と log.bats の間）
   - 注: README.md の `lib/` セクションには既に `hooks.sh` が記載されている

## 実装ステップ

1. AGENTS.md の `lib/` セクションに `hooks.sh` エントリを追加
2. AGENTS.md の `test/lib/` セクションに `hooks.bats` エントリを追加
3. README.md の `test/lib/` セクションに `hooks.bats` エントリを追加
4. 変更をコミット

## テスト方針

- ドキュメント変更のみのため、手動確認で十分
- ファイル構造との整合性を確認

## リスクと対策

- リスク: 特になし（ドキュメント修正のみ）
- 対策: コミット前にファイル構造との整合性を再確認

## 受け入れ条件

- [x] AGENTS.md の `lib/` セクションに `hooks.sh` が追加される
- [ ] AGENTS.md の `test/lib/` セクションに `hooks.bats` が追加される
- [ ] README.md の `test/lib/` セクションに `hooks.bats` が追加される
