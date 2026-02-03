---
name: pi-issue-runner
description: GitHub IssueからGit worktreeを作成し、tmuxセッション内で別のpiインスタンスを起動してタスクを実行します。並列開発に最適。
---

# Pi Issue Runner

GitHub Issueを入力として、Git worktreeを作成し、tmuxセッション内で独立したpiインスタンスを起動します。

## クイックリファレンス

```bash
# Issue実行（メインコマンド）
# デフォルトでpi終了後に自動クリーンアップ
scripts/run.sh <issue-number> [options]

Options:
  -w, --workflow <name>  ワークフロー名（デフォルト: default）
  --list-workflows       利用可能なワークフロー一覧を表示
  --no-attach            バックグラウンドで起動
  --no-cleanup           自動クリーンアップを無効化
  --reattach             既存セッションにアタッチ
  --force                強制再作成
  -b, --branch <name>    カスタムブランチ名
  --base <branch>        ベースブランチ
  --agent-args <args>    エージェントに渡す追加の引数
  --pi-args <args>       --agent-args のエイリアス（後方互換性）
  --ignore-blockers      依存関係チェックをスキップして強制実行

# バッチ実行（依存関係順）
scripts/run-batch.sh <issue>... [options]
scripts/run-batch.sh 42 43 44 --dry-run     # 実行計画のみ表示
scripts/run-batch.sh 42 43 44 --sequential  # 順次実行

# セッション管理
scripts/list.sh                          # セッション一覧
scripts/dashboard.sh                     # プロジェクトダッシュボード
scripts/dashboard.sh --compact           # サマリーのみ表示
scripts/dashboard.sh --json              # JSON出力
scripts/dashboard.sh --watch             # 自動更新（5秒ごと）
scripts/attach.sh <session>              # セッションにアタッチ
scripts/status.sh <session>              # 状態確認
scripts/stop.sh <session>                # セッション停止
scripts/cleanup.sh <session>             # 手動クリーンアップ
scripts/force-complete.sh <session>      # セッション強制完了
scripts/force-complete.sh 42 --error     # エラーとして完了

# メッセージ送信
scripts/nudge.sh <issue-number>          # セッションに続行を促すメッセージを送信
scripts/nudge.sh 42 --message "続けてください"

# CI修正ワークフロー
scripts/run.sh 42 --workflow ci-fix       # CI失敗の自動修正

# 継続的改善
scripts/improve.sh                    # レビュー→Issue作成→実行→待機のループ
scripts/improve.sh --dry-run          # レビューのみ（Issue作成しない）
scripts/improve.sh --review-only      # 問題表示のみ
scripts/improve.sh --max-iterations 2 # 最大2回繰り返す
scripts/improve.sh --auto-continue    # 自動継続（承認スキップ）
scripts/wait-for-sessions.sh 42 43    # 複数セッション完了待機
```

## 前提条件

- **Bash 4.0以上** (macOSの場合: `brew install bash`)
- `gh` (GitHub CLI、認証済み)
- `tmux`
- `pi`
- `jq` (JSON処理)
- `yq` (オプション - ワークフローのカスタマイズに必要)

## 自動クリーンアップ

タスク完了時またはエラー発生時にAIが特定のマーカーを出力すると、
`watch-session.sh` が検出して適切な処理を実行します。

### マーカー形式

| マーカー | 説明 | 動作 |
|----------|------|------|
| `###TASK_COMPLETE_<issue_number>###` | 正常完了 | 自動クリーンアップ実行 |
| `###TASK_ERROR_<issue_number>###` | エラー発生 | 通知送信、手動対応待ち |

### 動作フロー

1. `run.sh` がバックグラウンドで `watch-session.sh` を起動
2. `watch-session.sh` がtmuxセッションの出力を監視
3. マーカー（例: `###TASK_COMPLETE_42###` または `###TASK_ERROR_42###`）を検出
4. 完了マーカーの場合は自動的に `cleanup.sh` を実行、エラーマーカーの場合は通知を送信

### 自動クリーンアップの無効化

```bash
# 自動クリーンアップを無効化
scripts/run.sh 42 --no-cleanup
```

### メッセージ送信

実行中のセッションにメッセージを送信して、続行を促すことができます。

```bash
# セッションにメッセージを送信（続行を促す）
scripts/nudge.sh <issue-number> [options]
scripts/nudge.sh 42 --message "続けてください"
```

| オプション | 説明 |
|-----------|------|
| `-m, --message TEXT` | 送信するメッセージ（デフォルト: "続けてください"） |
| `-s, --session NAME` | セッション名を明示的に指定 |

## 詳細ドキュメント

詳しい使い方、設定、トラブルシューティングは [README.md](README.md) を参照してください。
