# 変更履歴 (CHANGELOG)

Pi Issue Runnerの主要な変更履歴です。

## [Unreleased]

### Added
- **CI自動修正機能** (`lib/ci-fix.sh`, `lib/ci-monitor.sh`, `lib/ci-retry.sh`, `lib/ci-classifier.sh`)
  - CI失敗の自動検出と分類
  - 自動修正リトライ管理
  - CI状態監視
- **バッチ実行機能** (`scripts/run-batch.sh`, `lib/batch.sh`, `lib/dependency.sh`)
  - 複数Issueの依存関係順実行
  - レイヤー計算とトポロジカルソート
- **セッション管理強化**
  - `scripts/force-complete.sh` - セッション強制完了
  - `scripts/nudge.sh` - セッションへメッセージ送信
- `docs/overview.md` - プロジェクトの設計思想と価値を文書化
- `docs/CHANGELOG.md` - 変更履歴の追跡

## [2026-01-31] - Hook機能とセキュリティ強化

### Added
- **Hook機能** (`lib/hooks.sh`, `docs/hooks.md`)
  - `on_start`: セッション開始時のカスタム処理
  - `on_success`: タスク正常完了時の通知
  - `on_error`: エラー検出時のアラート
  - `on_cleanup`: クリーンアップ完了後の処理
  - テンプレート変数サポート（`{{issue_number}}`, `{{error_message}}`等）
  - 環境変数経由での値受け渡し

- **セキュリティ強化** (`docs/security.md`)
  - Issue本文のサニタイズ処理
  - プロンプトインジェクション対策
  - Hookスクリプトのセキュリティガイドライン

- **クリーンアップ機能拡張** (`scripts/cleanup.sh`)
  - `--all` オプション: 全セッションの一括クリーンアップ
  - `--age <hours>` オプション: 指定時間以上経過したセッションのみ削除
  - 孤立したworktreeの警告表示

### Changed
- `lib/workflow.sh` からテンプレート処理を `lib/template.sh` に分離
- YAMLパーサーを `lib/yaml.sh` に統合
- `watch-session.sh` の起動時マーカー検出を改善

### Fixed
- エージェントテンプレート内での誤ったマーカー検出を防止
- `lib/*.sh` が `SCRIPT_DIR` を上書きする問題を修正
- `improve.sh` の変数スコープ問題を修正

## [2026-01-30] - 自動クリーンアップとワークフロー

### Added
- **自動クリーンアップ機能** (`scripts/watch-session.sh`)
  - 完了マーカー（`###TASK_COMPLETE_<issue>###`）の検出
  - バックグラウンドでのセッション監視
  - 自動的なworktree/セッション削除
  - `--no-cleanup` オプションで無効化可能

- **ワークフローエンジン** (`lib/workflow.sh`, `workflows/`)
  - `default.yaml`: 計画→実装→レビュー→マージの完全ワークフロー
  - `simple.yaml`: 実装→マージの簡易ワークフロー
  - カスタムワークフローのサポート
  - `--workflow` オプションでワークフロー指定

- **エージェントテンプレート** (`agents/`)
  - `plan.md`: 実装計画の作成
  - `implement.md`: コードの実装
  - `review.md`: マルチペルソナセルフレビュー
  - `merge.md`: PR作成とマージ

- **継続的改善** (`scripts/improve.sh`)
  - プロジェクトレビュー→Issue作成→実行のループ
  - `--max-iterations` で反復回数制限
  - `--dry-run` でレビューのみ実行
  - `--auto-continue` で承認ゲートスキップ

- **複数セッション待機** (`scripts/wait-for-sessions.sh`)
  - 複数Issue番号の完了待機
  - `--timeout` でタイムアウト設定
  - `--fail-fast` でエラー即時終了

### Changed
- プロンプト生成を `@file` 参照方式に変更
- セッション名の命名規則を `pi-issue-{番号}` に統一

## [2026-01-29] - 基盤機能の安定化

### Added
- **プロジェクト初期化** (`scripts/init.sh`)
  - `.pi-runner.yaml` の自動生成
  - `.worktrees/` ディレクトリ作成
  - `.gitignore` の自動更新
  - `--full` で完全セットアップ
  - `--minimal` で最小セットアップ

- **設定管理強化** (`lib/config.sh`)
  - 環境変数による設定上書き
  - 設定ファイル読み込みの優先順位
  - デフォルト値のフォールバック

- **並列実行制御** (`lib/tmux.sh`)
  - `max_concurrent` による同時実行数制限
  - アクティブセッション数のカウント
  - 制限超過時のエラーメッセージ

### Changed
- Bash 4.0以上を必須に（連想配列サポートのため）
- 設定ファイル名を `.pi-runner.yaml` に統一

### Fixed
- `set -e` との互換性問題を修正
- worktree出力のパース問題を修正
- `setup_cleanup_trap` の変数スコープ問題を修正

## [2026-01-28] - テストフレームワーク導入

### Added
- **Batsテストフレームワーク** (`test/`)
  - `test/lib/` - ライブラリのユニットテスト
  - `test/scripts/` - スクリプトの統合テスト
  - `test/regression/` - 回帰テスト
  - `test/fixtures/` - テスト用フィクスチャ
  - `test_helper.bash` - 共通ヘルパー関数

- **テスト実行スクリプト** (`scripts/test.sh`)
  - `./scripts/test.sh` - 全テスト実行
  - `./scripts/test.sh lib` - ライブラリテストのみ
  - `./scripts/test.sh scripts` - スクリプトテストのみ
  - `--shellcheck` - 静的解析
  - `--all` - Bats + ShellCheck

- **モック関数** (`test_helper.bash`)
  - `mock_gh` - GitHub CLIのモック
  - `mock_tmux` - tmuxのモック
  - `enable_mocks` - モックの有効化

### Changed
- ログ出力を `lib/log.sh` に統一
- エラーハンドリングを改善

## [2026-01-27] - CLI強化

### Added
- **セッション管理コマンド**
  - `scripts/list.sh` - セッション一覧表示
  - `scripts/status.sh` - 状態確認
  - `scripts/attach.sh` - セッションアタッチ
  - `scripts/stop.sh` - セッション停止

- **実行オプション**
  - `--reattach` - 既存セッションへの再アタッチ
  - `--force` - 強制再作成
  - `--no-attach` - バックグラウンド実行
  - `--pi-args` - piへの追加引数

- **クリーンアップオプション**
  - `--delete-branch` - ブランチも削除
  - `--keep-session` - セッションを保持
  - `--keep-worktree` - worktreeを保持

### Changed
- ステータス管理をJSON形式に変更
- セッション名の検索をIssue番号でも可能に

## [2026-01-26] - 初期リリース

### Added
- **コア機能**
  - GitHub Issue取得 (`lib/github.sh`)
  - Git worktree作成・削除 (`lib/worktree.sh`)
  - Tmuxセッション管理 (`lib/tmux.sh`)
  - 設定ファイル読み込み (`lib/config.sh`)

- **メインスクリプト**
  - `scripts/run.sh` - Issue実行
  - `scripts/cleanup.sh` - クリーンアップ

- **ドキュメント**
  - `SPECIFICATION.md` - 仕様書
  - `architecture.md` - アーキテクチャ設計
  - `README.md` - 使用方法
  - `AGENTS.md` - 開発ガイド
  - `SKILL.md` - piスキル定義

- **設定**
  - `.pi-runner.yaml` - 設定ファイル形式
  - 環境変数サポート

### Technical Decisions
- シェルスクリプトベースの実装（依存最小化）
- Git worktreeによる並列作業環境
- Tmuxによるセッション管理
- GitHub CLIによるIssue連携

---

## バージョニング方針

このプロジェクトは日付ベースのバージョニングを採用しています。

- **メジャー変更**: 破壊的変更（APIの非互換）
- **マイナー変更**: 新機能追加
- **パッチ変更**: バグ修正、ドキュメント更新

## 関連ドキュメント

- [overview.md](./overview.md) - 設計思想
- [SPECIFICATION.md](./SPECIFICATION.md) - 詳細仕様
- [architecture.md](./architecture.md) - アーキテクチャ
