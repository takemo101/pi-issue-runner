# Issue #270 実装計画書

## 概要

クローズ済みIssueの計画書を自動削除する機能を追加する。

## 影響範囲

| ファイル | 変更内容 |
|---------|---------|
| `scripts/cleanup.sh` | `--delete-plans` オプションを追加 |
| `agents/merge.md` | 計画書削除ステップを追加 |
| `docs/plans/README.md` | ドキュメント更新 |
| `test/scripts/cleanup.bats` | テスト追加 |
| `docs/plans/issue-*.md` | 不要な計画書を削除 (#240, #242, #246, #247) |

## 実装ステップ

### 1. cleanup.sh に --delete-plans オプションを追加

- `--delete-plans` フラグを追加
- クローズ済みIssueの計画書を一括削除する機能
- `--dry-run` との組み合わせをサポート
- `gh` CLIを使用してIssueの状態を確認

### 2. merge.md エージェントを更新

- マージ完了後に計画書を削除するステップを追加
- `rm -f docs/plans/issue-{{issue_number}}-plan.md` を実行

### 3. 既存の計画書を削除

- #240, #242, #246, #247 の計画書を削除

### 4. ドキュメント更新

- `docs/plans/README.md` を更新して新機能を記載

### 5. テスト追加

- `cleanup.sh --delete-plans` のテストを追加
- dry-run モードのテスト

## テスト方針

1. **単体テスト**
   - `--delete-plans` オプションがヘルプに表示される
   - `--delete-plans --dry-run` で削除対象が表示される
   - `--delete-plans` で実際に削除される

2. **手動テスト**
   - 実際にクローズ済みIssueの計画書が削除されることを確認

## リスクと対策

| リスク | 対策 |
|-------|------|
| 誤って必要な計画書を削除 | `--dry-run` オプションで事前確認可能 |
| gh CLIが利用不可 | エラーメッセージで対処法を表示 |

## 完了条件

- [x] Issueの要件を完全に理解した
- [x] 関連するコードを調査した
- [x] 実装計画書を作成した
- [x] 計画書をファイルに保存した
