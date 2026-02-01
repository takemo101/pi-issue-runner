# 実装計画: Issue #464

## 概要

ドキュメント内で設定ファイルの拡張子表記を統一します（.yml → .yaml）。

プロジェクトの設定ファイルは `.pi-runner.yaml`（.yaml拡張子）を使用しているが、一部のドキュメントで `.yml` 拡張子が使用されている箇所を修正します。

## 影響範囲

- `docs/plans/issue-433-plan.md` (line 6)

## 実装ステップ

1. `docs/plans/issue-433-plan.md` の line 6 を修正:
   - Before: `.pi-runner.yml`
   - After: `.pi-runner.yaml`

## テスト方針

- 検証コマンドで該当箇所が0件になることを確認:
  ```bash
  grep -rn "\.pi-runner\.yml" docs/
  ```

## リスクと対策

- リスクなし - 単純なドキュメント修正
