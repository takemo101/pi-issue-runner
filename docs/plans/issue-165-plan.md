# Implementation Plan: Issue #165

## 概要

`improve.sh`の`###CREATED_ISSUES###`マーカー抽出が、ANSIエスケープコードや制御文字が含まれている場合に失敗する問題を修正する。

## 影響範囲

- **scripts/improve.sh** - `review_and_create_issues`関数のマーカー抽出ロジック
- **test/improve_test.sh** - ANSIコード・制御文字付き入力のテストケース追加

## 実装ステップ

### 1. マーカー抽出ロジックの改善

`review_and_create_issues`関数のIssue番号抽出部分を修正:

1. ANSIエスケープコードの除去 (`\x1b\[[0-9;]*m`)
2. キャリッジリターンの除去 (`\r`)
3. デバッグログの追加 (`LOG_LEVEL=DEBUG`時)

修正前:
```bash
issues_text=$(sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' "$output_file" \
    | grep -oE '[0-9]+' \
    | head -n "$max_issues") || true
```

修正後:
```bash
# ANSIエスケープコードと制御文字を除去してから処理
issues_text=$(cat "$output_file" \
    | tr -d '\r' \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | sed -n '/###CREATED_ISSUES###/,/###END_ISSUES###/p' \
    | grep -oE '[0-9]+' \
    | head -n "$max_issues") || true
```

### 2. デバッグログの追加

`LOG_LEVEL=DEBUG`時にマーカー抽出の詳細をログ出力:
- 出力ファイルのサイズ
- マーカー検出の有無
- 抽出されたIssue番号

### 3. テストケースの追加

- ANSIエスケープコード付き入力のテスト
- キャリッジリターン付き入力のテスト
- Unicode空白文字付き入力のテスト

## テスト方針

1. 単体テスト: `test/improve_test.sh`に新規テストケース追加
2. 手動テスト: `LOG_LEVEL=DEBUG ./scripts/improve.sh --dry-run`で動作確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| sedの互換性（GNU vs BSD） | macOS/LinuxどちらでもテストするまたはPOSIX準拠の記法を使用 |
| 正規表現の誤マッチ | 既存テストと新規テストで回帰を防止 |
| パフォーマンス低下 | パイプラインは1回のみ通すため影響軽微 |

## 見積もり

- 実装: 30分
- テスト: 30分
- レビュー: 15分
- 合計: 約1.25時間
