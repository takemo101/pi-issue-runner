---
name: pi-issue-runner
description: GitHub IssueからGit worktreeを作成し、tmuxセッション内で別のpiインスタンスを起動してタスクを実行します。並列開発に最適。
---

# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、tmuxセッション内で独立したpiインスタンスを起動します。

## クイックリファレンス

```bash
# Issue実行（メインコマンド）
scripts/run.sh <issue-number> [options]

Options:
  --no-attach       バックグラウンドで起動
  --reattach        既存セッションにアタッチ
  --force           強制再作成
  --auto-cleanup    セッション終了時に自動クリーンアップ
  --no-cleanup      クリーンアッププロンプトを無効化
  --branch <name>   カスタムブランチ名
  --base <branch>   ベースブランチ
  --pi-args <args>  piへの追加引数

# セッション管理
scripts/list.sh              # セッション一覧
scripts/attach.sh <session>  # セッションにアタッチ
scripts/status.sh <session>  # 状態確認
scripts/stop.sh <session>    # セッション停止
scripts/cleanup.sh <session> # クリーンアップ
```

## 前提条件

- `gh` (GitHub CLI、認証済み)
- `tmux`
- `pi`
- `jq` (JSON処理)

## 詳細ドキュメント

詳しい使い方、設定、トラブルシューティングは [README.md](README.md) を参照してください。
