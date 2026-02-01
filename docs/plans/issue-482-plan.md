# Issue #482 実装計画

## 概要

GitHub GraphQL APIを使用してIssueのブロッカー（依存関係）を取得する機能を `lib/github.sh` に追加します。

## 実装する機能

1. **get_issue_blockers()** - Issueのブロッカー一覧を取得する関数
2. **check_issue_blocked()** - Issueがブロックされているかチェックする関数

## 影響範囲

- `lib/github.sh` - 新規関数の追加
- `test/lib/github.bats` - テストの追加

## 実装ステップ

### 1. lib/github.sh に関数を追加

#### get_issue_blockers()
- 引数: issue_number
- 戻り値: JSON配列 `[{number, title, state}, ...]`
- GraphQL APIを使用して `blockedBy` フィールドを取得
- リポジトリ情報は `gh repo view --json owner,name` で動的に取得
- エラーハンドリング（認証エラー、Issue not found等）

#### check_issue_blocked()
- 引数: issue_number
- 戻り値: 0=ブロックされていない, 1=ブロックされている
- OPEN状態のブロッカーをフィルタリング
- ブロックされている場合、ブロッカー情報をstdoutに出力

### 2. テストを追加

- `get_issue_blockers` の正常系・異常系テスト
- `check_issue_blocked` の正常系・異常系テスト
- GraphQL APIエラーのハンドリングテスト
- jqパイプ処理のテスト

## 技術的考慮事項

1. **GraphQLクエリ構造**
   ```graphql
   query($owner: String!, $repo: String!, $number: Int!) {
     repository(owner: $owner, name: $repo) {
       issue(number: $number) {
         blockedBy(first: 20) {
           nodes {
             number
             title
             state
           }
         }
       }
     }
   }
   ```

2. **エラーハンドリング**
   - `gh api graphql` のエラーを適切に処理
   - Issueが見つからない場合は空配列を返す
   - GraphQLエラーの場合はログ出力して空配列を返す

3. **jqパイプ処理**
   - `gh api graphql` の出力から `.data.repository.issue.blockedBy.nodes` を抽出
   - 結果がnullの場合は空配列 `[]` を返す

## テスト方針

1. **正常系**
   - ブロッカーが存在する場合の取得
   - ブロッカーが空の場合は空配列
   - OPEN/CLOSED状態のブロッカー取得

2. **異常系**
   - Issueが存在しない場合
   - GraphQL APIエラーの場合
   - jqが未インストールの場合

3. **check_issue_blocked**
   - OPENブロッカーあり → return 1
   - 全ブロッカーCLOSED → return 0
   - ブロッカーなし → return 0

## リスクと対策

| リスク | 対策 |
|--------|------|
| GraphQL APIが利用できない | REST API fallbackは今回実装しない（将来的に検討） |
| blockedByフィールドが存在しない | 空配列を返す |
| 認証エラー | `check_gh_cli` で事前チェック |

## 推定工数

- 実装: 30分
- テスト: 30分
- レビュー・修正: 15分
- **合計: 約75分**
