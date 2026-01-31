# 実装計画: Issue #144 - エラー検知と通知機能の追加

## 概要

バックグラウンドで実行中のセッションでエラーが発生した場合に、ユーザーにmacOS通知を表示し、自動的にTerminal.appを開いてセッションにアタッチする機能を実装する。

## 影響範囲

### 新規作成
- `lib/notify.sh` - 通知・ステータス管理ライブラリ

### 変更対象
- `scripts/watch-session.sh` - エラーマーカー検知機能追加
- `scripts/list.sh` - エラーステータス表示対応
- `agents/implement.md` - エラー報告の指示追加
- `agents/merge.md` - エラー報告の指示追加
- `agents/review.md` - エラー報告の指示追加
- `agents/plan.md` - エラー報告の指示追加

### ランタイムディレクトリ
- `.worktrees/.status/` - ステータスJSONファイル格納ディレクトリ

## 実装ステップ

### Step 1: lib/notify.sh の作成

通知とステータス管理の共通ライブラリを作成:

```bash
# 機能:
# - notify_error(): macOS通知を表示
# - open_terminal_and_attach(): Terminal.appでセッションにアタッチ
# - save_status(): ステータスファイルを保存
# - load_status(): ステータスファイルを読み込み
# - get_status_dir(): ステータスディレクトリパスを取得
```

### Step 2: watch-session.sh の拡張

エラーマーカー検知ロジックを追加:

1. `###TASK_ERROR_<issue>###` マーカーの検知
2. エラー検知時に `notify_error()` 呼び出し
3. ステータスファイルへの書き込み
4. `--no-auto-attach` オプション対応

### Step 3: list.sh の拡張

ステータス列を追加:

```
SESSION         ISSUE   STATUS    ERROR
pi-issue-140    #140    running   -
pi-issue-141    #141    error     PRマージ失敗
pi-issue-142    #142    complete  -
```

### Step 4: エージェントテンプレートの更新

全エージェントテンプレートにエラー報告セクションを追加:

```markdown
## エラー報告

回復不能なエラーが発生した場合は、以下のマーカーを出力してください：

\`\`\`
###TASK_ERROR_{{issue_number}}###
エラーの説明
\`\`\`
```

### Step 5: テストの作成

- `test/notify_test.sh` - notify.sh のユニットテスト
- 既存テストへの追加

## テスト方針

### ユニットテスト
- `notify.sh` の各関数のテスト
- ステータスファイルの読み書きテスト
- エラーマーカー検知ロジックのテスト

### 統合テスト（手動）
- 実際のtmuxセッションでエラーマーカー出力→通知確認
- `list.sh` でのステータス表示確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| macOS依存 (osascript) | 環境チェック関数を追加、Linux用のフォールバック用意 |
| Terminal.app前提 | 将来的にiTerm2対応を検討 (今回はスコープ外) |
| ステータスファイル競合 | ファイルロック不要（1セッション1ファイル） |
| エラーメッセージのサニタイズ | AppleScript用にエスケープ処理 |

## 見積もり

| タスク | 時間 |
|--------|------|
| lib/notify.sh 作成 | 30分 |
| watch-session.sh 拡張 | 1時間 |
| list.sh 拡張 | 30分 |
| エージェントテンプレート更新 | 15分 |
| テスト作成 | 45分 |
| **合計** | **約3時間** |

## 完了条件

- [x] 実装計画書を作成した
- [ ] lib/notify.sh を作成した
- [ ] watch-session.sh を拡張した
- [ ] list.sh を拡張した
- [ ] エージェントテンプレートを更新した
- [ ] テストを作成し、全てパスした
