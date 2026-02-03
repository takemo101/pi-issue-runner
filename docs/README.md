# Pi Issue Runner ドキュメント

Pi Issue Runnerの詳細な仕様とアーキテクチャドキュメント。

## 🎯 このプロジェクトについて

Pi Issue Runnerは、**AIエージェントによる並列開発**を実現するための基盤ツールです。
GitHub Issueを入力として、独立したworktree環境でpiインスタンスを並列実行し、
複数のタスクを同時に処理できます。

→ **[設計思想と価値を詳しく読む](./overview.md)**

## 📚 目次

### 概要

- **[overview.md](./overview.md)** - 設計思想と価値
  - なぜこの仕組みが重要なのか
  - 設計原則
  - ユースケース
  - 技術的決定とトレードオフ

- **[CHANGELOG.md](./CHANGELOG.md)** - 変更履歴
  - バージョンごとの変更内容
  - 追加機能、修正、破壊的変更

### 仕様書

- **[SPECIFICATION.md](./SPECIFICATION.md)** - 全体仕様概要
  - 目的と主要機能
  - コアコンセプト
  - データモデル
  - 非機能要件
  - 将来の拡張性

### アーキテクチャ設計

- **[architecture.md](./architecture.md)** - システムアーキテクチャ
  - システム構成とレイヤー構成
  - コンポーネント設計
  - データフロー
  - エラーハンドリング
  - セキュリティとパフォーマンス

### 機能詳細

- **[worktree-management.md](./worktree-management.md)** - Git Worktree管理
  - Worktree作成・削除
  - ファイルコピー
  - エッジケース処理
  - パフォーマンス最適化

- **[tmux-integration.md](./tmux-integration.md)** - Tmux統合
  - セッション管理
  - コマンド実行
  - 出力キャプチャ
  - ログ管理

- **[parallel-execution.md](./parallel-execution.md)** - 並列実行
  - 同時実行制御
  - タスクキュー管理
  - 依存関係解決
  - リソース管理

- **[state-management.md](./state-management.md)** - 状態管理
  - データ永続化
  - トランザクション管理
  - キャッシュ
  - バックアップとリストア

- **[configuration.md](./configuration.md)** - 設定
  - 設定ファイルフォーマット
  - 設定項目の詳細
  - 環境変数
  - ベストプラクティス

- **[security.md](./security.md)** - セキュリティ
  - 入力サニタイズ
  - プロンプトインジェクション対策
  - 安全なコマンド実行
  - ベストプラクティス

- **[workflows.md](./workflows.md)** - ワークフロー
  - ビルトインワークフロー（default, simple）
  - カスタムワークフローの作成
  - エージェントテンプレート

- **[hooks.md](./hooks.md)** - Hook機能
  - ライフサイクルイベント
  - カスタムスクリプト実行
  - 通知設定

## 🚀 クイックリンク

### はじめての方

- [設計思想と価値](./overview.md) - なぜこの仕組みが重要か
- [変更履歴](./CHANGELOG.md) - 最新の変更内容
- [仕様概要](./SPECIFICATION.md) - 全体像を把握

### 開発者向け

- [システム構成図](./architecture.md#システム構成)
- [ディレクトリ構造](./SPECIFICATION.md#ディレクトリ構造)
- [API設計](./architecture.md#2-library-layer-lib)
- [エラーハンドリング](./architecture.md#エラーハンドリング)

### 運用者向け

- [設定ガイド](./configuration.md)
- [トラブルシューティング](./worktree-management.md#トラブルシューティング)
- [パフォーマンスチューニング](./parallel-execution.md#パフォーマンス最適化)
- [クリーンアップ戦略](./state-management.md#クリーンアップ)

## 📖 ドキュメントの読み方

### 初めて読む方

1. [overview.md](./overview.md) - 設計思想と価値を理解
2. [SPECIFICATION.md](./SPECIFICATION.md) - 全体像を把握
3. [architecture.md](./architecture.md) - システム設計を理解
4. [configuration.md](./configuration.md) - 設定方法を学ぶ

### 機能実装する方

1. [architecture.md](./architecture.md) - レイヤー構成を確認
2. 該当する機能のドキュメント（worktree, tmux, parallel, state）を参照
3. [SPECIFICATION.md](./SPECIFICATION.md#ディレクトリ構造) - データ構造を確認

### トラブルシューティング

1. 該当する機能のドキュメント内の「トラブルシューティング」セクション
2. [state-management.md](./state-management.md#監視と復旧) - 監視と復旧
3. [configuration.md](./configuration.md#トラブルシューティング) - 設定問題

## 🔄 ドキュメント更新履歴

詳細は [CHANGELOG.md](./CHANGELOG.md) を参照してください。

- **2026-02-03**: CI機能とバッチ処理
  - CI自動修正機能（ci-fix, ci-monitor, ci-retry, ci-classifier）
  - バッチ実行機能（run-batch.sh, dependency.sh）
  - セッション管理強化（force-complete, nudge）

- **2026-01-31**: Hook機能とセキュリティ強化
  - Hook機能（on_start, on_success, on_error, on_cleanup）
  - セキュリティドキュメント
  - 設計思想ドキュメント（overview.md）
  - 変更履歴（CHANGELOG.md）

- **2026-01-30**: 自動クリーンアップとワークフロー
  - 自動クリーンアップ機能
  - ワークフローエンジン
  - 継続的改善スクリプト

- **2026-01-29**: 基盤機能の安定化
  - プロジェクト初期化
  - 設定管理強化
  - 並列実行制御

- **2026-01-26**: 初版作成
  - 全体仕様書
  - アーキテクチャ設計
  - 主要機能の詳細仕様

## 📝 ドキュメント規約

### ファイル命名

- `SPECIFICATION.md` - 全体仕様（大文字）
- `{機能名}.md` - 機能別仕様（小文字、ハイフン区切り）
- `README.md` - インデックス（各ディレクトリ）

### Markdown記法

- **見出し**: H1は1つ、H2以降で構造化
- **コードブロック**: 言語を明示（```typescript, ```bash等）
- **リンク**: 相対パスで関連ドキュメントへリンク
- **図**: Mermaid記法またはASCII図

### コード例

- **実装例**: 実際に動作するコード
- **擬似コード**: 概念を説明する簡略化されたコード
- **設定例**: YAMLまたはJSON形式

## 🤝 ドキュメント貢献

ドキュメントの改善提案は歓迎します：

1. Issueを作成して問題点を報告
2. PRでドキュメントを修正
3. 不明点や追加したい内容をDiscussionで議論

### ドキュメント改善のポイント

- ✅ 具体例を追加
- ✅ 図表で視覚化
- ✅ トラブルシューティング情報を追加
- ✅ ベストプラクティスを共有
- ✅ 実装経験からのTipsを追記

## 📚 参考資料

### 外部ドキュメント

- [Git Worktree](https://git-scm.com/docs/git-worktree)
- [Tmux Documentation](https://github.com/tmux/tmux/wiki)
- [GitHub REST API](https://docs.github.com/en/rest)
- [Pi Mono](https://github.com/badlogic/pi-mono)

### 関連プロジェクト

- [orchestrator-hybrid](https://github.com/takemo101/orchestrator-hybrid) - インスピレーション元
- [Ralph Orchestrator](https://github.com/ralphscheid/ralph-orchestrator) - ループベースオーケストレーション

## ❓ よくある質問

### Q: どのドキュメントから読めば良い？

A: 初めての方は [SPECIFICATION.md](./SPECIFICATION.md) から、実装する方は [architecture.md](./architecture.md) から読むことをお勧めします。

### Q: ドキュメントが古い・間違っている

A: Issueまたは PRを作成してください。実装とドキュメントの乖離を防ぐため、PRには関連ドキュメントの更新も含めてください。

### Q: もっと詳しく知りたい機能がある

A: Discussionで質問するか、ドキュメント拡充のIssueを作成してください。

## 📄 ライセンス

このドキュメントはプロジェクトと同じライセンス（MIT）で提供されます。
