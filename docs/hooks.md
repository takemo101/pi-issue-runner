# Hook機能

pi-issue-runnerは、セッションのライフサイクルイベントでカスタムスクリプトを実行できるhook機能をサポートしています。

## 対応イベント

### セッションライフサイクル

| イベント | 発火タイミング |
|----------|----------------|
| `on_start` | セッション開始時 |
| `on_success` | タスク正常完了時 |
| `on_error` | エラー検出時 |
| `on_cleanup` | クリーンアップ完了後 |

### 継続的改善（improve.sh）ライフサイクル

| イベント | 発火タイミング |
|----------|----------------|
| `on_improve_start` | improve.sh 全体の開始時 |
| `on_improve_end` | improve.sh 全体の終了時 |
| `on_iteration_start` | 各イテレーション開始時 |
| `on_iteration_end` | 各イテレーション完了時 |
| `on_review_complete` | レビュー完了・Issue作成前 |

## 設定方法

`.pi-runner.yaml` の `hooks` セクションで設定します。

### スクリプトファイル指定

以下はユーザーが作成するスクリプトの例です。`hooks/` ディレクトリおよびスクリプトファイルはプロジェクトに同梱されていません。

```yaml
hooks:
  on_start: ./hooks/on-start.sh
  on_success: ./hooks/on-success.sh
  on_error: ./hooks/on-error.sh
  on_cleanup: ./hooks/on-cleanup.sh
```

### インラインコマンド

> **⚠️ セキュリティ注意**: インラインhookコマンドはデフォルトで無効化されています。使用するには `.pi-runner.yaml` で `hooks.allow_inline: true` を設定するか、環境変数 `PI_RUNNER_ALLOW_INLINE_HOOKS=true` を設定してください。セキュリティの観点から、可能な限り[スクリプトファイル](#スクリプトファイル指定)を使用することを推奨します。詳細は[セキュリティドキュメント](./security.md#インラインhookの制御)を参照してください。

> **🔒 環境変数のサニタイズ**: `PI_ISSUE_TITLE` および `PI_ERROR_MESSAGE` に含まれる制御文字（改行、タブ、ヌル文字等）は自動的に除去されます。これにより、Issueタイトルやエラーメッセージに含まれる特殊文字が `bash -c` 内で意図しない動作を引き起こすことを防ぎます。

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

方法1: `.pi-runner.yaml` で設定（推奨）

```yaml
hooks:
  allow_inline: true
  on_success: |
    echo "Issue #$PI_ISSUE_NUMBER completed"
```

方法2: 環境変数で設定

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

### セッション関連

| 環境変数 | 説明 | 利用可能イベント |
|----------|------|-----------------|
| `PI_ISSUE_NUMBER` | Issue番号 | on_start, on_success, on_error, on_cleanup |
| `PI_ISSUE_TITLE` | Issueタイトル | on_start, on_success, on_error, on_cleanup |
| `PI_SESSION_NAME` | セッション名 | on_start, on_success, on_error, on_cleanup |
| `PI_BRANCH_NAME` | ブランチ名 | on_start, on_success, on_error, on_cleanup |
| `PI_WORKTREE_PATH` | worktreeパス | on_start, on_success, on_error, on_cleanup |
| `PI_ERROR_MESSAGE` | エラーメッセージ | on_error |
| `PI_EXIT_CODE` | 終了コード | on_error, on_cleanup |

### 継続的改善（improve.sh）関連

| 環境変数 | 説明 | 利用可能イベント |
|----------|------|-----------------|
| `PI_ITERATION` | 現在のイテレーション番号 | on_iteration_start, on_iteration_end, on_review_complete |
| `PI_MAX_ITERATIONS` | 最大イテレーション数 | on_improve_start, on_improve_end, on_iteration_start, on_iteration_end, on_review_complete |
| `PI_ISSUES_CREATED` | 作成されたIssue数 | on_iteration_end, on_improve_end |
| `PI_ISSUES_SUCCEEDED` | 成功したIssue数 | on_iteration_end, on_improve_end |
| `PI_ISSUES_FAILED` | 失敗したIssue数 | on_iteration_end, on_improve_end |
| `PI_REVIEW_ISSUES_COUNT` | レビューで発見された問題数 | on_review_complete |

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

### 継続的改善（improve.sh）の進捗通知

```yaml
hooks:
  on_improve_start: |
    osascript -e 'display notification "改善プロセスを開始します" with title "Pi Issue Runner" subtitle "🔄 Iteration $PI_ITERATION/$PI_MAX_ITERATIONS"'
  on_review_complete: |
    echo "📋 Review found $PI_REVIEW_ISSUES_COUNT issues"
  on_iteration_start: |
    echo "📍 Starting iteration $PI_ITERATION/$PI_MAX_ITERATIONS"
  on_iteration_end: |
    osascript -e 'display notification "Iteration $PI_ITERATION 完了: $PI_ISSUES_SUCCEEDED 成功 / $PI_ISSUES_FAILED 失敗" with title "Pi Issue Runner"'
  on_improve_end: |
    osascript -e 'display notification "改善プロセス完了: 全 $PI_ISSUES_CREATED 件中 $PI_ISSUES_SUCCEEDED 件成功" with title "Pi Issue Runner" sound name "Glass"'
```

### 継続的改善の統計記録

```yaml
hooks:
  on_iteration_end: |
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"),iteration-$PI_ITERATION,created=$PI_ISSUES_CREATED,succeeded=$PI_ISSUES_SUCCEEDED,failed=$PI_ISSUES_FAILED" >> .improve-stats.csv
  on_improve_end: |
    echo "Improve iteration $PI_ITERATION complete: $PI_ISSUES_SUCCEEDED/$PI_ISSUES_CREATED succeeded" >> .improve-summary.log
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
