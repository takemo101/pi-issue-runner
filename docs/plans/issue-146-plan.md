# Issue #146 実装計画: 継続的改善スクリプト (improve.sh) の追加

## 概要

プロジェクトレビュー→Issue作成→並列実行→完了待ち→再レビューのループを自動化するスクリプトを追加する。

## 影響範囲

### 新規ファイル
- `lib/status.sh` - ステータス管理機能（notify.shから抽出・拡張）
- `scripts/wait-for-sessions.sh` - 複数セッション完了待機
- `scripts/improve.sh` - 継続的改善メインスクリプト
- `test/status_test.sh` - ステータス機能テスト
- `test/wait_for_sessions_test.sh` - 待機機能テスト

### 既存ファイル変更
- `lib/notify.sh` - status.shをsourceするように変更（互換性維持）
- `scripts/watch-session.sh` - 既にステータス機能使用中（変更不要）

## 設計判断

### ステータス管理について
既存の`lib/notify.sh`に既にステータス管理機能が存在:
- `save_status()`, `load_status()`, `get_status_value()`, `get_error_message()`

Issue要件では`lib/status.sh`として分離を求めているため:
1. `lib/status.sh`に純粋なステータス管理機能を配置
2. `lib/notify.sh`は`status.sh`をsourceして通知機能に専念
3. 後方互換性を維持

## 実装ステップ

### Step 1: lib/status.sh 作成
- notify.shからステータス関連関数を抽出
- `set_status()`エイリアス追加（Issue仕様に合わせる）
- `get_status()`エイリアス追加

### Step 2: lib/notify.sh 修正
- status.shをsource
- 既存関数を維持（互換性）
- 重複コードを削減

### Step 3: scripts/wait-for-sessions.sh 作成
- 複数Issue番号を引数で受け取り
- ポーリングで全セッション完了を待機
- `--timeout`オプション
- エラー発生時は即座にエラー通知

### Step 4: scripts/improve.sh 作成
- メインループ実装
- `--max-iterations`, `--max-issues`, `--auto-continue`, `--dry-run`オプション
- piを呼び出してproject-reviewを実行
- 作成されたIssue番号の抽出

### Step 5: テスト作成
- `test/status_test.sh` - ステータス機能の単体テスト
- `test/wait_for_sessions_test.sh` - 待機機能のテスト（モック使用）

## テスト方針

1. **単体テスト**: 個別関数のテスト
2. **統合テスト**: モック環境での動作確認
3. **手動テスト**: 実際のIssueを使った動作確認

## リスクと対策

| リスク | 対策 |
|--------|------|
| piコマンドの出力形式変更 | マーカー形式を明確に定義 |
| 無限ループ | --max-iterations で制限 |
| 並列実行数超過 | 既存のcheck_concurrent_limitを活用 |
| 通知の重複 | ステータスファイルで状態管理 |

## 完了条件チェックリスト

- [ ] `lib/status.sh` でステータスファイルを管理できる
- [ ] `watch-session.sh` がステータスファイルを更新する（既存）
- [ ] `wait-for-sessions.sh` で複数セッションの完了を待機できる
- [ ] `improve.sh` でレビュー→実行→待機のループが動作する
- [ ] `--max-iterations` で最大回数を制限できる
- [ ] `--dry-run` でレビューのみ実行できる
- [ ] 承認ゲートで次のイテレーションを制御できる
- [ ] テストがパスする
