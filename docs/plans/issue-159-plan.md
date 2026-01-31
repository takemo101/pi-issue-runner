# Issue #159 実装計画

## 概要

pi-issue-runnerをグローバルインストールするためのスクリプト（install.sh、uninstall.sh）を追加し、任意のディレクトリで`pi-run 42`のようなコマンドを実行できるようにする。

## 影響範囲

### 新規作成ファイル
- `install.sh` - グローバルインストールスクリプト
- `uninstall.sh` - アンインストールスクリプト

### 更新ファイル
- `README.md` - インストールセクションの更新

## 実装ステップ

### 1. install.sh の作成
- シンボリックリンクを `$HOME/.local/bin` に作成
- 環境変数 `INSTALL_DIR` でカスタマイズ可能
- コマンドマッピング:
  - `pi-run` → `scripts/run.sh`
  - `pi-list` → `scripts/list.sh`
  - `pi-attach` → `scripts/attach.sh`
  - `pi-status` → `scripts/status.sh`
  - `pi-stop` → `scripts/stop.sh`
  - `pi-cleanup` → `scripts/cleanup.sh`
  - `pi-improve` → `scripts/improve.sh`
  - `pi-wait` → `scripts/wait-for-sessions.sh`
  - `pi-watch` → `scripts/watch-session.sh` （既存スクリプト）
- PATH未設定の場合に警告を表示

### 2. uninstall.sh の作成
- シンボリックリンクを削除
- 存在するリンクのみ削除

### 3. README.md の更新
- グローバルインストールセクションを追加
- 使用例を追加

## テスト方針

### 手動テスト
1. `./install.sh` を実行し、シンボリックリンクが作成されることを確認
2. 作成されたコマンドが実行可能であることを確認
3. `./uninstall.sh` を実行し、リンクが削除されることを確認

### テスト内容
- カスタム `INSTALL_DIR` での動作
- 既存リンクがある場合の上書き動作
- PATH警告の表示

## リスクと対策

### リスク1: 既存コマンドとの名前衝突
- **対策**: `pi-` プレフィックスで衝突を回避

### リスク2: シンボリックリンクの絶対パス依存
- **対策**: `$SCRIPT_DIR` を使用して相対パスから絶対パスを解決

### リスク3: 権限問題
- **対策**: ユーザー領域（`$HOME/.local/bin`）をデフォルトに使用

## 見積もり

- install.sh: 30分
- uninstall.sh: 15分
- README更新: 15分
- テスト: 30分
- **合計: 1.5時間**
