# Implementation Plan: Issue #155

## 概要

`improve.sh`の`review_and_create_issues`関数がIssue番号を抽出する際、先頭スペースがある行を正しく処理できないバグを修正する。

## 原因分析

問題のコード（233-235行目）:
```bash
issues_text=$(sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$output_file" \
    | grep -E '^[0-9]+$' \
    | head -n "$max_issues") || true
```

`grep -E '^[0-9]+$'` は行頭が数字で始まることを要求するため、以下のような入力で失敗する:
```
 ###CREATED_ISSUES###
 152
 153
 ###END_ISSUES###
```

## 影響範囲

- `scripts/improve.sh` - `review_and_create_issues`関数のIssue番号抽出部分
- 影響を受けるモード: 通常モード（`dry_run=false`, `review_only=false`）のみ

## 実装ステップ

### Step 1: Issue番号抽出ロジックの修正

修正案: `grep -oE '[0-9]+'` を使用して、行内の数字のみを抽出する。

**修正前:**
```bash
issues_text=$(sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$output_file" \
    | grep -E '^[0-9]+$' \
    | head -n "$max_issues") || true
```

**修正後:**
```bash
issues_text=$(sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$output_file" \
    | grep -oE '[0-9]+' \
    | head -n "$max_issues") || true
```

### Step 2: テストの追加

`test/improve_test.sh` を新規作成し、Issue番号抽出のテストケースを追加:
- 空白なしの正常ケース
- 先頭スペースありのケース
- 末尾スペースありのケース
- マーカーが見つからないケース
- Issue番号がないケース

## テスト方針

1. **単体テスト**: `test/improve_test.sh` でIssue番号抽出ロジックをテスト
2. **手動テスト**: 実際にスペースを含む出力ファイルを作成してテスト

## リスクと対策

| リスク | 対策 |
|--------|------|
| `grep -oE` が複数の数字を1行から抽出する | マーカー間の行のみを対象とするため問題なし |
| テキスト中の数字を誤抽出 | マーカーで囲まれた範囲のみを処理するため安全 |

## 見積もり

- 修正: 10分
- テスト追加: 15分
- レビュー: 5分
- **合計: 30分**
