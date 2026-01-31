# Issue #110 実装計画書

## 概要

テストディレクトリを `tests/` から `test/` に統一し、メンテナンス負担を軽減する。

## 現状分析

### `test/` ディレクトリ（10ファイル、メインで使用中）
- シェルスクリプト形式（`*_test.sh`）
- 自己完結型のテスト
- 高いカバレッジ

### `tests/` ディレクトリ（Bats形式、古い）
- `run_tests.sh` - Batsテスト実行スクリプト
- `scripts/*.bats` - 3ファイル（cleanup, status, run）
- `lib/*.bats` - 3ファイル（github, tmux, config）
- `fixtures/sample-config.yml` - **有用：移行対象**
- `helpers/mocks.sh` - **有用：移行対象**

## 影響範囲

1. `tests/` ディレクトリ - 削除
2. `test/` ディレクトリ - fixtures, helpers追加
3. `AGENTS.md` - テスト説明の更新

## 実装ステップ

1. `tests/fixtures/` を `test/fixtures/` に移動
2. `tests/helpers/` を `test/helpers/` に移動
3. `tests/` ディレクトリを削除
4. `AGENTS.md` を更新（Bats関連の記述を削除）

## テスト方針

- 既存の `test/*_test.sh` が引き続き動作することを確認
- `./test/config_test.sh` で代表テスト実行

## リスクと対策

| リスク | 対策 |
|--------|------|
| fixtures/helpersの参照パス変更 | 移行後、helpersは直接使用されていないため影響なし |
| Batsテストの喪失 | test/のシェルスクリプトテストで同等以上のカバレッジあり |
