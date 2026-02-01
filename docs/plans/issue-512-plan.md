# Issue #512 実装計画書

## 概要

ビルトインワークフロー `workflows/thorough.yaml` で定義されている `test` ステップに対応するエージェントテンプレート `agents/test.md` を作成します。

## 影響範囲

### 変更対象ファイル
- **作成**: `agents/test.md` - テストエージェントテンプレート（新規）
- **修正**: `workflows/thorough.yaml` - コメント削除（オプション）
- **修正**: `docs/workflows.md` - ドキュメント更新

### 関連ファイル
- `agents/plan.md` - スタイル参照用
- `agents/implement.md` - スタイル参照用
- `agents/review.md` - スタイル参照用
- `agents/merge.md` - スタイル参照用

## 実装ステップ

### Step 1: agents/test.md の作成

既存のエージェントテンプレート（plan.md, implement.md, review.md, merge.md）と同じ構造・スタイルで作成：

1. **ヘッダー**: `# Test Agent`
2. **重要な注意書き**: 非対話的実行に関する警告
3. **コンテキスト**: テンプレート変数（issue_number, issue_title, branch_name, worktree_path）
4. **タスク**:
   - ユニットテスト実行
   - 統合テスト実行
   - テストカバレッジ確認
   - 問題があれば修正
5. **完了条件**: チェックリスト形式
6. **エラー報告**: 標準的なエラーマーカー形式

### Step 2: workflows/thorough.yaml の更新（オプション）

コメント `# カスタムステップ: agents/test.md が必要` を削除または更新

### Step 3: ドキュメント更新

`docs/workflows.md` に `thorough` ワークフローの説明と `test` ステップの情報を追加

### Step 4: テスト

```bash
# ファイルが正しく配置されていることを確認
ls -la agents/test.md

# テンプレート構文の検証
grep -E '\{\{issue_number\}\}' agents/test.md
grep -E '\{\{branch_name\}\}' agents/test.md
```

## テスト方針

1. **ファイル構成テスト**:
   - `agents/test.md` が存在すること
   - 適切なパーミッションを持つこと

2. **テンプレート構文テスト**:
   - 全ての標準変数が含まれていること
   - 構文が他のエージェントと一致していること

3. **統合テスト**:
   - `thorough` ワークフローが正常に読み込めること
   - `test` ステップで `agents/test.md` が見つかること

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| テンプレート変数の不一致 | 中 | 既存エージェントと同じ変数名を使用 |
| スタイルの不整合 | 低 | 既存エージェントの構造を厳密にコピー |
| ドキュメントの欠落 | 低 | 実装後に必ずドキュメントを更新 |

## 完了条件

- [ ] `agents/test.md` が作成される
- [ ] 既存エージェントと同じ構造・スタイルである
- [ ] `docs/workflows.md` が更新される
- [ ] テストがパスする

## 参考情報

### 既存エージェントの構成パターン

```markdown
# [Name] Agent

[重要な注意書き]

## コンテキスト
- **変数**: {{variable}}

## タスク
1. [タスク内容]

## 完了条件
- [ ] [チェック項目]

## エラー報告
[エラーマーカー形式]
```

### 標準テンプレート変数

- `{{issue_number}}` - Issue番号
- `{{issue_title}}` - Issueタイトル
- `{{branch_name}}` - ブランチ名
- `{{worktree_path}}` - 作業ディレクトリパス
