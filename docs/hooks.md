# Hook機能

pi-issue-runnerは、セッションのライフサイクルイベントでカスタムスクリプトを実行できるhook機能をサポートしています。

## 対応イベント

| イベント | 発火タイミング |
|----------|----------------|
| `on_start` | セッション開始時 |
| `on_success` | タスク正常完了時 |
| `on_error` | エラー検出時 |
| `on_cleanup` | クリーンアップ完了後 |

## 設定方法

`.pi-runner.yaml` の `hooks` セクションで設定します。

### スクリプトファイル指定

```yaml
hooks:
  on_start: ./hooks/on-start.sh
  on_success: ./hooks/on-success.sh
  on_error: ./hooks/on-error.sh
  on_cleanup: ./hooks/on-cleanup.sh
```

### インラインコマンド

```yaml
hooks:
  on_success: |
    terminal-notifier -title "完了" -message "Issue #{{issue_number}} が完了しました"
  on_error: |
    osascript -e 'display notification "エラー発生" with title "Pi Issue Runner"'
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"text": "Issue #{{issue_number}} でエラー: {{error_message}}"}' \
      $SLACK_WEBHOOK_URL
```

### 特定イベントのみ設定

```yaml
hooks:
  on_error: ./hooks/on-error.sh  # エラー時のみhookを実行
```

## テンプレート変数

hookコマンド/スクリプト内で使用可能な変数：

| 変数 | 説明 | 利用可能イベント |
|------|------|-----------------|
| `{{issue_number}}` | Issue番号 | 全て |
| `{{issue_title}}` | Issueタイトル | 全て |
| `{{session_name}}` | セッション名 | 全て |
| `{{branch_name}}` | ブランチ名 | 全て |
| `{{worktree_path}}` | worktreeパス | 全て |
| `{{error_message}}` | エラーメッセージ | on_error |
| `{{exit_code}}` | 終了コード | 全て |

## 環境変数

hookスクリプトには環境変数としても値が渡されます：

| 環境変数 | 説明 |
|----------|------|
| `PI_ISSUE_NUMBER` | Issue番号 |
| `PI_ISSUE_TITLE` | Issueタイトル |
| `PI_SESSION_NAME` | セッション名 |
| `PI_BRANCH_NAME` | ブランチ名 |
| `PI_WORKTREE_PATH` | worktreeパス |
| `PI_ERROR_MESSAGE` | エラーメッセージ（on_errorのみ） |
| `PI_EXIT_CODE` | 終了コード |

### 環境変数の使用例

```bash
#!/bin/bash
# hooks/on-success.sh

echo "Issue #$PI_ISSUE_NUMBER completed"
echo "Session: $PI_SESSION_NAME"
echo "Branch: $PI_BRANCH_NAME"

# Slack通知
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    curl -X POST -H 'Content-Type: application/json' \
        -d "{\"text\": \"Issue #$PI_ISSUE_NUMBER が完了しました\"}" \
        "$SLACK_WEBHOOK_URL"
fi
```

## デフォルト動作

hookが設定されていない場合：

- **on_success**: macOS/Linux通知を表示
- **on_error**: macOS/Linux通知を表示
- **on_start**: 何もしない
- **on_cleanup**: 何もしない

## 使用例

### Slack通知

```yaml
hooks:
  on_success: |
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"text": ":white_check_mark: Issue #{{issue_number}} 完了"}' \
      $SLACK_WEBHOOK_URL
  on_error: |
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"text": ":x: Issue #{{issue_number}} でエラー: {{error_message}}"}' \
      $SLACK_WEBHOOK_URL
```

### Discord通知

```yaml
hooks:
  on_success: |
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"content": "Issue #{{issue_number}} が完了しました"}' \
      $DISCORD_WEBHOOK_URL
```

### カスタムログ記録

```yaml
hooks:
  on_start: echo "[$(date)] Issue #{{issue_number}} started" >> ~/.pi-runner/activity.log
  on_success: echo "[$(date)] Issue #{{issue_number}} completed" >> ~/.pi-runner/activity.log
  on_error: echo "[$(date)] Issue #{{issue_number}} error: {{error_message}}" >> ~/.pi-runner/activity.log
```

### macOS通知（カスタマイズ）

```yaml
hooks:
  on_success: |
    osascript -e 'display notification "Issue #{{issue_number}} が完了しました" with title "Pi Runner" sound name "Glass"'
  on_error: |
    osascript -e 'display notification "{{error_message}}" with title "Pi Runner エラー" sound name "Basso"'
```

## エラーハンドリング

hookスクリプトでエラーが発生しても、pi-issue-runnerのメイン処理は継続します。hookのエラーはログに記録されますが、セッションの監視やクリーンアップには影響しません。

## 関連ドキュメント

- [設定ファイル](./configuration.md)
- [ワークフロー](./workflows.md)
