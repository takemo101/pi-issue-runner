# 実装計画: Issue #255

## 概要

`test/fixtures/sample-config.yaml` ファイルの冒頭コメントを実際のファイルパスに修正する。

## 現状

- **現在のコメント**: `# tests/fixtures/sample-config.yml`
- **正しいコメント**: `# test/fixtures/sample-config.yaml`

### 差分
| 項目 | 現在 | 正しい値 |
|------|------|----------|
| ディレクトリ | `tests` | `test` |
| 拡張子 | `.yml` | `.yaml` |

## 影響範囲

- `test/fixtures/sample-config.yaml` - 1行目のコメントのみ

## 実装ステップ

1. `test/fixtures/sample-config.yaml` の1行目を修正
2. 変更をコミット

## テスト方針

- コメントのみの変更のため、テストの修正は不要
- 既存テストがパスすることを確認

## リスクと対策

- リスク: なし（コメントのみの変更）
