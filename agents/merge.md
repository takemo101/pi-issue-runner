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

### 4. クリーンアップ（オプション）
マージ後、ローカル環境をクリーンアップします：

```bash
# メインブランチに戻る
git checkout main
git pull

# ローカルブランチを削除
git branch -d {{branch_name}}
```

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
