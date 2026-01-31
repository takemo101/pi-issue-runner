# Issue #111 実装計画書

## 概要

Issue本文にサニタイズ処理を追加し、悪意あるシェルコマンドがプロンプトに渡されるリスクを軽減する。

## 現状分析

### 問題点
1. `scripts/run.sh` の164行目で `get_issue_body()` によりIssue本文を取得
2. `lib/workflow.sh` の `generate_workflow_prompt()` でIssue本文がそのままプロンプトファイルに書き込まれる
3. Issue本文に悪意あるシェルコマンドが含まれる可能性がある

### リスクシナリオ
- Issue本文に `$(rm -rf /)` などのコマンド置換が含まれている
- バッククォート内にコマンドが含まれている
- 特殊文字によるエスケープシーケンス攻撃

## 影響範囲

- `lib/github.sh` - サニタイズ関数追加
- `scripts/run.sh` - サニタイズ処理の適用
- `test/tmux_test.sh` または `test/github_test.sh` - テスト追加

## 実装ステップ

### 1. サニタイズ関数の追加（lib/github.sh）

```bash
# Issue本文のサニタイズ
# - 危険なパターンの検出・警告
# - コマンド置換パターンのエスケープ
sanitize_issue_body() {
    local body="$1"
    local warnings=""
    
    # 危険なパターンの検出
    # 1. コマンド置換 $(...)
    # 2. バッククォート `...`
    # 3. 環境変数展開 ${...}
    
    # パターンを検出して警告ログを出力
    # 実際のエスケープ処理を適用
    
    echo "$sanitized_body"
}
```

### 2. run.shでの適用

```bash
# Issue本文取得後にサニタイズ
issue_body="$(get_issue_body "$issue_number" 2>/dev/null)" || issue_body=""
issue_body="$(sanitize_issue_body "$issue_body")"
```

### 3. 単体テストの追加

```bash
@test "sanitize_issue_body removes command substitution" {
    local body='Test $(whoami) text'
    local result=$(sanitize_issue_body "$body")
    [[ "$result" != *'$(whoami)'* ]]
}
```

## テスト方針

1. **単体テスト**: サニタイズ関数の各パターン検出テスト
2. **手動テスト**: 実際にIssueを作成してrun.shを実行

### テストケース
- コマンド置換 `$(...)` パターン
- バッククォート `` `...` `` パターン
- 変数展開 `${...}` パターン
- 通常テキスト（変更なし）
- 混合パターン

## リスクと対策

| リスク | 対策 |
|--------|------|
| 誤検出による正当な内容の変更 | 警告ログを出力し、ユーザーに通知 |
| 新しい攻撃パターンの出現 | 将来的なパターン追加が容易な設計 |
| パフォーマンス低下 | 軽量な正規表現による検出 |

## 完了条件

- [x] Issueの要件を完全に理解した
- [x] 関連するコードを調査した
- [x] 実装計画書を作成した
- [x] 計画書をファイルに保存した
