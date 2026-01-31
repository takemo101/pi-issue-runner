# 計画書 (Plans)

このディレクトリは、GitHub Issue の実装計画書を一時的に保管するためのものです。

## ライフサイクル

```
Issue作成 → 計画書作成 → 実装 → PRマージ → 計画書削除
```

1. **作成**: Issue 実装開始時に `issue-<番号>-plan.md` として作成
2. **参照**: 実装中に必要に応じて更新・参照
3. **削除**: PR マージ後、計画書は削除される

## 方針

- 計画書は **一時的なドキュメント** として扱う
- Issue と PR に十分な情報が記録されるため、マージ後は不要
- 過去の計画書が必要な場合は **Git 履歴** から参照可能

## ファイル命名規則

```
issue-<issue番号>-plan.md
```

例: `issue-123-plan.md`

## クリーンアップ

クローズ済み Issue の計画書を削除するには:

```bash
gh issue list --state closed --json number -q ".[].number" | while read num; do
  rm -f docs/plans/issue-$num-plan.md
done
```

> **Note**: 計画書は PR マージ後に自動削除されないため、定期的なクリーンアップを推奨します。
