# Issue #314 実装計画書

## cleanup: docs/plans/のクローズ済みIssue計画書24件を削除

## 概要

`docs/plans/README.md` の方針に反して残存しているクローズ済みIssueの計画書24件を削除する。

## 影響範囲

- `docs/plans/issue-*-plan.md` - 24ファイル削除対象

### 削除対象ファイル一覧

| Issue番号 | ステータス | ファイル |
|-----------|----------|----------|
| #250 | CLOSED | issue-250-plan.md |
| #251 | CLOSED | issue-251-plan.md |
| #254 | CLOSED | issue-254-plan.md |
| #255 | CLOSED | issue-255-plan.md |
| #258 | CLOSED | issue-258-plan.md |
| #260 | CLOSED | issue-260-plan.md |
| #262 | CLOSED | issue-262-plan.md |
| #263 | CLOSED | issue-263-plan.md |
| #265 | CLOSED | issue-265-plan.md |
| #266 | CLOSED | issue-266-plan.md |
| #272 | CLOSED | issue-272-plan.md |
| #273 | CLOSED | issue-273-plan.md |
| #275 | CLOSED | issue-275-plan.md |
| #281 | CLOSED | issue-281-plan.md |
| #284 | CLOSED | issue-284-plan.md |
| #285 | CLOSED | issue-285-plan.md |
| #288 | CLOSED | issue-288-plan.md |
| #289 | CLOSED | issue-289-plan.md |
| #292 | CLOSED | issue-292-plan.md |
| #293 | CLOSED | issue-293-plan.md |
| #294 | CLOSED | issue-294-plan.md |
| #295 | CLOSED | issue-295-plan.md |
| #296 | CLOSED | issue-296-plan.md |
| #297 | CLOSED | issue-297-plan.md |

## 実装ステップ

1. `./scripts/cleanup.sh --delete-plans --dry-run` でプレビュー
2. `./scripts/cleanup.sh --delete-plans` で実行
3. 削除結果を確認
4. 変更をコミット

## テスト方針

- 削除後、`docs/plans/` にはREADME.mdと本計画書（issue-314-plan.md）のみが残ることを確認
- オープンIssueの計画書がないことも確認（現時点で存在しない）

## リスクと対策

- **リスク**: 必要なファイルを誤って削除
- **対策**: cleanup.shはGitHub APIでIssue状態を確認してから削除する
- **リカバリ**: Git履歴から復元可能

## 受け入れ条件

- [x] クローズ済みIssueの計画書がすべて削除されている
- [x] オープン中Issueの計画書は残っている（該当なし）
