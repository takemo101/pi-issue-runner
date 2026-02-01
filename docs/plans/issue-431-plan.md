# Implementation Plan: Issue #431

## 概要

AIが完了マーカーを出力しない場合に、セッションを強制的に完了させるスクリプト `scripts/force-complete.sh` を追加します。

## 要件分析

### ユースケース
1. AIがPR作成・マージ後に完了マーカーを出力し忘れた
2. AIが途中で停止して応答しなくなった
3. 手動でタスク完了を判断し、cleanupを実行したい

### 機能要件
- Issue番号またはセッション名を引数に受け取る
- セッションの存在確認
- 完了マーカー `###TASK_COMPLETE_${issue_number}###` をセッションに送信
- `--error` オプションでエラーマーカーを送信
- `--message` オプションでカスタムメッセージを追加
- watch-session.shがマーカーを検出して自動cleanupを実行

## 影響範囲

### 新規作成ファイル
- `scripts/force-complete.sh` - メインスクリプト
- `test/scripts/force-complete.bats` - Batsテスト

### 関連ファイル（参照のみ）
- `scripts/watch-session.sh` - マーカー検出とcleanup実行
- `lib/tmux.sh` - セッション操作関数
- `lib/log.sh` - ログ出力関数

## 実装ステップ

1. **スクリプト作成**
   - ヘッダ（shebang, set -euo pipefail）
   - ライブラリ読み込み（config.sh, log.sh, tmux.sh）
   - usage関数
   - main関数
     - 引数パース（issue number/session name, --error, --message）
     - セッション名解決
     - セッション存在確認
     - マーカー送信（tmux send-keys）

2. **テスト作成**
   - ヘルプオプションテスト
   - エラーケーステスト（引数なし、無効なオプション）
   - スクリプト構造テスト
   - オプション処理テスト

3. **動作確認**
   - シェルチェック
   - テスト実行
   - 手動テスト

## テスト方針

### 単体テスト（Bats）
- ヘルプ表示（-h, --help）
- 引数なしでのエラー
- 無効なオプションでのエラー
- スクリプト構造（syntax, source, function存在）
- オプション処理（--error, --message）

### 手動テスト
```bash
# 完了マーカーの送信
./scripts/force-complete.sh 42

# エラーマーカーの送信
./scripts/force-complete.sh 42 --error

# カスタムメッセージ付き
./scripts/force-complete.sh 42 --message "Manual completion"
```

## リスクと対策

| リスク | 対策 |
|--------|------|
| 存在しないセッションを指定 | tmux has-sessionで確認し、エラーメッセージを表示 |
| 無効なIssue番号 | 数値チェックを実施 |
| メッセージに特殊文字が含まれる | 適切なクォーティング |
| tmuxがインストールされていない | lib/tmux.shのcheck_tmuxで検出 |

## 実装方針

### コードスタイル
- 既存スクリプト（stop.sh, attach.sh）に準拠
- 関数構成: usage(), main()
- エラーハンドリング: set -euo pipefail
- ログ出力: lib/log.shを使用

### マーカー形式
- 完了マーカー: `###TASK_COMPLETE_${issue_number}###`
- エラーマーカー: `###TASK_ERROR_${issue_number}###`
- watch-session.shと完全に互換性のある形式

### 引数仕様
```
Usage: force-complete.sh <session-name|issue-number> [options]

Options:
    --error         エラーマーカーを送信
    --message <msg> カスタムメッセージを追加
    -h, --help      ヘルプ表示
```
