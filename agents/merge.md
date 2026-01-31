# Merge Agent

GitHub Issue #{{issue_number}} のPRを作成し、マージします。

## コンテキスト

- **Issue番号**: #{{issue_number}}
- **タイトル**: {{issue_title}}
- **ブランチ**: {{branch_name}}
- **作業ディレクトリ**: {{worktree_path}}

## タスク

### 1. プッシュ
```bash
git push -u origin {{branch_name}}
```

### 2. PR作成
```bash
gh pr create \
  --title "<type>: {{issue_title}}" \
  --body "## Summary
Closes #{{issue_number}}

## Changes
- <変更内容を記載>

## Testing
- <テスト内容を記載>"
```

### 3. PRのマージ
CIがパスしたことを確認してからマージします：

```bash
# CI状態を確認
gh pr checks

# マージ
gh pr merge --merge --delete-branch
```

### 4. クリーンアップ

> **Note**: Worktreeのクリーンアップは自動的に行われます。
> 手動でクリーンアップが必要な場合は `scripts/cleanup.sh` を使用してください。

## コミットタイプ

- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメント
- `refactor`: リファクタリング
- `test`: テスト追加
- `chore`: メンテナンス

## 完了条件

- [ ] コードがリモートにプッシュされた
- [ ] PRが作成された
- [ ] CIがパスした
- [ ] PRがマージされた
- [ ] リモートブランチが削除された

## 完了報告

全てのタスクが正常に完了した場合は、以下のマーカーを出力してください：

```
###TASK_COMPLETE_{{issue_number}}###
```

これにより、worktreeとセッションが自動的にクリーンアップされます。

> **重要**: このマーカーは外部プロセス（`watch-session.sh`）によって監視されています。
> マーカーを出力しないと、worktreeとtmuxセッションが残り続けます。

## エラー報告

回復不能なエラーが発生した場合は、以下のマーカーを出力してください：

```
###TASK_ERROR_{{issue_number}}###
エラーの説明（例: PRマージに失敗しました。CIが失敗しています。）
```

これにより、ユーザーに通知が送信され、手動での対応が可能になります。
