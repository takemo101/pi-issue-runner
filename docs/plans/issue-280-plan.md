# Implementation Plan: Issue #280 - Event Hook機能の追加

## 概要

セッションのライフサイクルイベント（on_start, on_success, on_error, on_cleanup）でカスタムスクリプトを実行できるhook機能を追加する。

## 影響範囲

| ファイル | 変更内容 |
|----------|----------|
| `lib/hooks.sh` | 新規作成 - hook実行エンジン |
| `lib/config.sh` | hooks設定の読み込み対応 |
| `lib/yaml.sh` | 複雑なYAMLパス対応（既存機能で対応可能） |
| `scripts/watch-session.sh` | on_success/on_errorフックの呼び出し |
| `scripts/run.sh` | on_startフックの呼び出し |
| `scripts/cleanup.sh` | on_cleanupフックの呼び出し |
| `test/lib/hooks.bats` | 新規作成 - hookテスト |
| `docs/hooks.md` | 新規作成 - ドキュメント |

## 実装ステップ

### Step 1: lib/hooks.sh の作成

1. `get_hook(event)` - 設定からhookを取得
2. `run_hook(event, ...)` - hookを実行
3. `_run_default_hook(event, ...)` - デフォルト動作（現在のnotify.sh相当）
4. 環境変数の設定とテンプレート変数展開

### Step 2: lib/config.sh の修正

1. hooks設定の読み込み対応
2. `get_hook_config(event)` 関数の追加

### Step 3: scripts/watch-session.sh の修正

1. hooks.sh のソース
2. `handle_complete()` → `run_hook("on_success", ...)`
3. `handle_error()` → `run_hook("on_error", ...)`

### Step 4: scripts/run.sh の修正

1. hooks.sh のソース
2. セッション開始時に `run_hook("on_start", ...)`

### Step 5: scripts/cleanup.sh の修正

1. hooks.sh のソース
2. クリーンアップ後に `run_hook("on_cleanup", ...)`

### Step 6: テストの追加

1. `test/lib/hooks.bats` の作成
2. 各イベントのテスト
3. テンプレート変数展開のテスト
4. 環境変数のテスト

### Step 7: ドキュメントの追加

1. `docs/hooks.md` の作成
2. README.md への参照追加

## テスト方針

### ユニットテスト（test/lib/hooks.bats）

- [ ] `get_hook()` がhooks設定を正しく取得
- [ ] `run_hook()` がスクリプトファイルを実行
- [ ] `run_hook()` がインラインコマンドを実行
- [ ] テンプレート変数が正しく展開される
- [ ] 環境変数が正しく設定される
- [ ] hook未設定時はデフォルト動作

### 統合テスト（test/scripts/watch-session.bats）

- [ ] on_success hookが呼び出される
- [ ] on_error hookが呼び出される

## リスクと対策

| リスク | 対策 |
|--------|------|
| hookスクリプトのエラーでセッション監視が止まる | hook実行を`|| true`でラップ |
| テンプレート変数の特殊文字でsedが壊れる | sedのデリミタを`|`に変更、エスケープ処理 |
| 既存の通知機能との競合 | hook未設定時は現在の動作を維持 |
| YAMLマルチライン対応 | yaml.shの既存機能を活用 |

## 完了条件

- [ ] lib/hooks.shを新規作成
- [ ] .pi-runner.yamlでhooksセクションをサポート
- [ ] on_start, on_success, on_error, on_cleanupイベントをサポート
- [ ] スクリプトファイルとインラインコマンドの両方をサポート
- [ ] テンプレート変数の展開
- [ ] 環境変数での値渡し
- [ ] hookが未設定の場合はデフォルト動作
- [ ] ドキュメント追加
- [ ] テスト追加
