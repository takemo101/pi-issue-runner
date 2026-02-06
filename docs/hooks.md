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

> **⚠️ セキュリティ注意**: インラインhookコマンドはデフォルトで無効化されています。使用するには環境変数 `PI_RUNNER_ALLOW_INLINE_HOOKS=true` を設定してください。セキュリティの観点から、可能な限り[スクリプトファイル](#スクリプトファイル指定)を使用することを推奨します。詳細は[セキュリティドキュメント](./security.md#インラインhookの制御)を参照してください。

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

**有効化方法**:

```bash
export PI_RUNNER_ALLOW_INLINE_HOOKS=true
./scripts/run.sh 42
```

### 特定イベントのみ設定

```yaml
hooks:
  on_error: ./hooks/on-error.sh  # エラー時のみhookを実行
```

## テンプレート変数（非推奨）

> **⚠️ 非推奨**: テンプレート変数（`{{...}}`）は**セキュリティ上の理由により非推奨**です。
> 代わりに[環境変数](#環境変数)を使用してください。詳細は[マイグレーションガイド](#マイグレーションガイド)を参照してください。

hookコマンド/スクリプト内で使用可能な変数（非推奨）：

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

## マイグレーションガイド

### テンプレート変数から環境変数への移行

テンプレート変数（`{{...}}`）は**セキュリティ上の理由により非推奨**となりました。環境変数を使用してください。

#### 問題点

テンプレート変数は文字列置換によって展開されるため、Issueタイトルやエラーメッセージに特殊文字（`;`, `"`, `` ` ``, `$()` 等）が含まれる場合、意図しないコマンドが実行される可能性があります。

**脆弱な例**:
```yaml
hooks:
  on_success: echo "Issue #{{issue_number}} completed"
```

Issueタイトルが `Fix bug"; rm -rf /; echo "` の場合、意図しないコマンドが実行される可能性があります。

#### 推奨される方法

環境変数を使用することで、特殊文字が安全に処理されます。

**安全な例**:
```yaml
hooks:
  on_success: echo "Issue #$PI_ISSUE_NUMBER completed"
```

### 変数対応表

| 非推奨: テンプレート変数 | 推奨: 環境変数 |
|-------------------------|---------------|
| `{{issue_number}}` | `$PI_ISSUE_NUMBER` |
| `{{issue_title}}` | `$PI_ISSUE_TITLE` |
| `{{session_name}}` | `$PI_SESSION_NAME` |
| `{{branch_name}}` | `$PI_BRANCH_NAME` |
| `{{worktree_path}}` | `$PI_WORKTREE_PATH` |
| `{{error_message}}` | `$PI_ERROR_MESSAGE` |
| `{{exit_code}}` | `$PI_EXIT_CODE` |

### 移行例

**変更前**（非推奨）:
```yaml
hooks:
  on_success: |
    terminal-notifier -title "完了" -message "Issue #{{issue_number}}: {{issue_title}}"
  on_error: |
    curl -X POST -H 'Content-Type: application/json' \
      -d '{"text": "Issue #{{issue_number}} でエラー: {{error_message}}"}' \
      $SLACK_WEBHOOK_URL
```

**変更後**（推奨）:
```yaml
hooks:
  on_success: |
    terminal-notifier -title "完了" -message "Issue #$PI_ISSUE_NUMBER: $PI_ISSUE_TITLE"
  on_error: |
    curl -X POST -H 'Content-Type: application/json' \
      -d "{\"text\": \"Issue #$PI_ISSUE_NUMBER でエラー: $PI_ERROR_MESSAGE\"}" \
      "$SLACK_WEBHOOK_URL"
```

### 注意事項

- テンプレート変数を使用している場合、非推奨警告が表示されます
- 環境変数は既に全てのhookで利用可能です
- 移行は互換性を保ちながら行われます（段階的に移行可能）

## 関連ドキュメント

- [設定ファイル](./configuration.md)
- [ワークフロー](./workflows.md)
- [セキュリティ](./security.md)
