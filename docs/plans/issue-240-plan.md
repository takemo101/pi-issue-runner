# Issue #240 実装計画

## 概要

README.mdのテスト構造セクションとドキュメントセクションを実際のディレクトリ構造と整合させる。

## 影響範囲

- `README.md` のみ

## 現状分析

### テスト構造の問題

| 記載内容 | 実際のディレクトリ |
|----------|-------------------|
| `test/helpers/mocks.sh` | 存在しない |
| - | `test/regression/` が存在 |

モック関数は `test/test_helper.bash` に含まれている。

### ドキュメントセクションの問題

以下のファイルへのリンクが欠落:
- `docs/state-management.md`
- `docs/SPECIFICATION.md`

## 実装ステップ

1. README.mdのテスト構造セクションを修正
   - `helpers/` と `mocks.sh` の記載を削除
   - `regression/` ディレクトリを追加
   - `test_helper.bash` にモック関数が含まれることを明記

2. README.mdのドキュメントセクションを修正
   - `docs/state-management.md` へのリンクを追加
   - `docs/SPECIFICATION.md` へのリンクを追加

## テスト方針

- ドキュメント修正のみのため、コード変更テストは不要
- リンク先ファイルの存在確認

## リスクと対策

- 低リスク: ドキュメント修正のみで機能への影響なし

## 見積もり

15分
