# Pi Issue Runner - Development Guide

## 概要

このプロジェクトは **シェルスクリプトベース** のpiスキルです。

## 技術スタック

- **言語**: Bash 4.3以上
- **依存ツール**: `gh` (GitHub CLI), `tmux`, `git`, `jq`, `yq` (YAMLパーサー、オプション)
- **テストフレームワーク**: Bats (Bash Automated Testing System)
- **静的解析**: ShellCheck

## ディレクトリ構造

```
pi-issue-runner/
├── .github/
│   ├── actions/
│   │   └── setup-deps/
│   │       └── action.yaml    # CI依存セットアップ（Bats, yq, tmux）
│   └── workflows/
│       └── ci.yaml    # CI設定
├── SKILL.md           # スキル定義（必須）
├── AGENTS.md          # 開発ガイド（このファイル）
├── README.md          # プロジェクト説明
├── install.sh         # グローバルインストール
├── uninstall.sh       # アンインストール
├── scripts/           # 実行スクリプト
│   ├── run.sh         # メインエントリーポイント
│   ├── run-batch.sh   # 複数Issueを依存関係順にバッチ実行
│   ├── restart-watcher.sh  # Watcher再起動
│   ├── init.sh        # プロジェクト初期化
│   ├── list.sh        # セッション一覧
│   ├── status.sh      # 状態確認
│   ├── attach.sh      # セッションアタッチ
│   ├── stop.sh        # セッション停止
│   ├── sweep.sh       # 全セッションのマーカーチェック・cleanup
│   ├── mux-all.sh     # 全セッション表示（マルチプレクサ対応）
│   ├── cleanup.sh     # クリーンアップ
│   ├── ci-fix-helper.sh  # CI修正ヘルパー（lib/ci-fix.shのラッパー）
│   ├── context.sh     # コンテキスト管理
│   ├── dashboard.sh   # ダッシュボード表示
│   ├── generate-config.sh  # プロジェクト解析・設定生成
│   ├── force-complete.sh  # セッション強制完了
│   ├── improve.sh     # 継続的改善スクリプト
│   ├── knowledge-loop.sh  # 知識ループ（fixコミットから知見抽出・AGENTS.md更新提案）
│   ├── next.sh        # 次のタスク取得
│   ├── nudge.sh       # セッションへメッセージ送信
│   ├── test.sh        # テスト一括実行
│   ├── tracker.sh     # プロンプト効果測定（集計・表示）
│   ├── verify-config-docs.sh  # 設定ドキュメントの整合性検証
│   ├── wait-for-sessions.sh  # 複数セッション完了待機
│   └── watch-session.sh  # セッション監視
├── lib/               # 共通ライブラリ
│   ├── agent.sh       # マルチエージェント対応
│   ├── batch.sh       # バッチ処理コア機能
│   ├── ci-classifier.sh   # CI失敗タイプ分類
│   ├── ci-fix.sh      # CI失敗検出・自動修正（※ci-fix-helper.sh経由で使用）
│   ├── ci-fix/            # CI修正サブモジュール群
│   │   ├── bash.sh        # Bash固有の修正・検証ロジック
│   │   ├── common.sh      # 共通ユーティリティ
│   │   ├── detect.sh      # プロジェクトタイプ検出
│   │   ├── escalation.sh  # エスカレーション処理
│   │   ├── go.sh          # Go固有の修正・検証ロジック
│   │   ├── node.sh        # Node固有の修正・検証ロジック
│   │   ├── python.sh      # Python固有の修正・検証ロジック
│   │   └── rust.sh        # Rust固有の修正・検証ロジック
│   ├── cleanup-trap.sh    # エラー時クリーンアップトラップ管理
│   ├── ci-monitor.sh      # CI状態監視
│   ├── ci-retry.sh        # CI自動修正リトライ管理
│   ├── cleanup-improve-logs.sh  # improve-logsのクリーンアップ
│   ├── cleanup-orphans.sh  # 孤立ステータスのクリーンアップ
│   ├── cleanup-plans.sh    # 計画書のローテーション
│   ├── compat.sh      # クロスプラットフォーム互換性ヘルパー
│   ├── config.sh      # 設定読み込み
│   ├── context.sh     # コンテキスト管理
│   ├── daemon.sh      # プロセスデーモン化
│   ├── dashboard.sh   # ダッシュボード機能
│   ├── dependency.sh  # 依存関係解析・レイヤー計算
│   ├── generate-config.sh  # プロジェクト解析・設定生成（ライブラリ関数）
│   ├── github.sh      # GitHub CLI操作
│   ├── hooks.sh       # Hook機能
│   ├── improve.sh     # 継続的改善ライブラリ（オーケストレーター）
│   ├── knowledge-loop.sh  # 知識ループコアライブラリ
│   ├── improve/       # 継続的改善モジュール群
│   │   ├── args.sh    # 引数解析
│   │   ├── deps.sh    # 依存関係チェック
│   │   ├── env.sh     # 環境セットアップ
│   │   ├── execution.sh # 実行・監視フェーズ
│   │   └── review.sh  # レビューフェーズ
│   ├── log.sh         # ログ出力
│   ├── marker.sh      # マーカー検出ユーティリティ
│   ├── notify.sh      # 通知機能
│   ├── priority.sh    # 優先度計算
│   ├── session-resolver.sh  # セッション名解決ユーティリティ
│   ├── status.sh      # 状態管理
│   ├── template.sh    # テンプレート処理
│   ├── tracker.sh     # プロンプト効果測定（記録コア）
│   ├── tmux.sh        # マルチプレクサ操作（後方互換ラッパー）
│   ├── multiplexer.sh      # マルチプレクサ抽象化レイヤー
│   ├── multiplexer-tmux.sh # tmux実装
│   ├── multiplexer-zellij.sh # Zellij実装
│   ├── workflow.sh    # ワークフローエンジン
│   ├── workflow-finder.sh   # ワークフロー検索
│   ├── workflow-loader.sh   # ワークフロー読み込み
│   ├── workflow-prompt.sh   # プロンプト処理
│   ├── workflow-selector.sh # ワークフロー自動選択（auto モード）
│   ├── worktree.sh    # Git worktree操作
│   └── yaml.sh        # YAMLパーサー
├── workflows/         # ビルトインワークフロー定義
│   ├── ci-fix.yaml    # CI修正ワークフロー
│   ├── default.yaml   # 完全ワークフロー
│   ├── simple.yaml    # 簡易ワークフロー
│   └── thorough.yaml  # 徹底ワークフロー
├── agents/            # エージェントテンプレート
│   ├── ci-fix.md      # CI修正エージェント
│   ├── improve-review.md  # improve.sh レビュープロンプト（カスタマイズ可能）
│   ├── plan.md        # 計画エージェント
│   ├── implement.md   # 実装エージェント
│   ├── review.md      # レビューエージェント
│   ├── test.md        # テストエージェント
│   └── merge.md       # マージエージェント
├── schemas/           # JSON Schema
│   └── pi-runner.schema.json  # .pi-runner.yaml のスキーマ
├── docs/              # ドキュメント
│   ├── README.md          # ドキュメント索引
│   ├── CHANGELOG.md       # 変更履歴
│   ├── SPECIFICATION.md   # 仕様書
│   ├── architecture.md    # アーキテクチャ
│   ├── coding-standards.md # コーディング規約
│   ├── configuration.md   # 設定リファレンス
│   ├── hooks.md           # Hook機能
│   ├── multi-workflow-design.md # マルチワークフロー設計
│   ├── overview.md        # 概要
│   ├── parallel-execution.md # 並列実行
│   ├── public-api.md        # 公開APIリファレンス
│   ├── security.md        # セキュリティ
│   ├── state-management.md # 状態管理
│   ├── multiplexer-integration.md # マルチプレクサ統合（tmux/Zellij）
│   ├── workflows.md       # ワークフロー
│   ├── worktree-management.md # Worktree管理
│   ├── memos/             # メモ・作業記録
│   │   └── README.md
│   └── plans/             # 計画書
│       └── README.md
├── test/              # Batsテスト（*.bats形式）
│   ├── lib/           # ライブラリのユニットテスト
│   │   ├── agent.bats
│   │   ├── batch.bats
│   │   ├── ci-classifier.bats  # ci-classifier.sh のテスト
│   │   ├── ci-fix.bats
│   │   ├── ci-fix/             # ci-fix サブモジュールのテスト
│   │   │   ├── bash.bats
│   │   │   ├── common.bats
│   │   │   ├── detect.bats
│   │   │   ├── escalation.bats
│   │   │   ├── go.bats
│   │   │   ├── node.bats
│   │   │   ├── python.bats
│   │   │   └── rust.bats
│   │   ├── ci-monitor.bats     # ci-monitor.sh のテスト
│   │   ├── ci-retry.bats       # ci-retry.sh のテスト
│   │   ├── cleanup-trap.bats
│   │   ├── cleanup-orphans.bats
│   │   ├── cleanup-improve-logs.bats  # cleanup-improve-logs.sh のテスト
│   │   ├── cleanup-plans.bats
│   │   ├── compat.bats
│   │   ├── config.bats
│   │   ├── context.bats
│   │   ├── daemon.bats
│   │   ├── dashboard.bats
│   │   ├── dependency.bats       # dependency.sh のテスト
│   │   ├── github.bats      # github.sh のテスト
│   │   ├── hooks.bats
│   │   ├── improve/       # improve サブモジュールのテスト
│   │   │   ├── args.bats
│   │   │   ├── deps.bats
│   │   │   ├── env.bats
│   │   │   ├── execution.bats
│   │   │   └── review.bats
│   │   ├── improve.bats
│   │   ├── knowledge-loop.bats  # knowledge-loop.sh のテスト
│   │   ├── log.bats
│   │   ├── marker.bats           # marker.sh のテスト
│   │   ├── notify.bats
│   │   ├── priority.bats
│   │   ├── session-resolver.bats
│   │   ├── status.bats
│   │   ├── template.bats
│   │   ├── tracker.bats
│   │   ├── multiplexer.bats
│   │   ├── multiplexer-tmux.bats
│   │   ├── multiplexer-zellij.bats
│   │   ├── tmux.bats
│   │   ├── workflow.bats
│   │   ├── workflow-finder.bats
│   │   ├── workflow-loader.bats
│   │   ├── workflow-prompt.bats
│   │   ├── workflow-selector.bats
│   │   ├── worktree.bats
│   │   └── yaml.bats
│   ├── scripts/       # スクリプトの統合テスト
│   │   ├── attach.bats
│   │   ├── ci-fix-helper.bats  # ci-fix-helper.sh のテスト
│   │   ├── cleanup.bats
│   │   ├── context.bats
│   │   ├── dashboard.bats
│   │   ├── force-complete.bats  # force-complete.sh のテスト
│   │   ├── generate-config.bats  # generate-config.sh のテスト
│   │   ├── improve.bats
│   │   ├── knowledge-loop.bats  # knowledge-loop.sh のテスト
│   │   ├── init.bats
│   │   ├── list.bats
│   │   ├── mux-all.bats         # mux-all.sh のテスト
│   │   ├── next.bats
│   │   ├── nudge.bats
│   │   ├── run.bats
│   │   ├── run-batch.bats        # run-batch.sh のテスト
│   │   ├── restart-watcher.bats  # restart-watcher.sh のテスト
│   │   ├── status.bats
│   │   ├── stop.bats
│   │   ├── sweep.bats            # sweep.sh のテスト
│   │   ├── test.bats
│   │   ├── tracker.bats
│   │   ├── verify-config-docs.bats
│   │   ├── wait-for-sessions.bats
│   │   └── watch-session.bats
│   ├── regression/    # 回帰テスト
│   │   ├── applescript-injection.bats
│   │   ├── cleanup-race-condition.bats
│   │   ├── config-master-table-dry.bats
│   │   ├── critical-fixes.bats
│   │   ├── escalation-literal-newline.bats
│   │   ├── eval-injection.bats
│   │   ├── hooks-env-sanitization.bats
│   │   ├── issue-1066-spaces-in-filenames.bats
│   │   ├── issue-1129-session-label-arg.bats
│   │   ├── issue-1145-duplicate-agent-override.bats
│   │   ├── issue-1198-duplicate-label-usage.bats
│   │   ├── issue-1211-uninstall-missing-commands.bats
│   │   ├── issue-1220-inline-hook-env.bats
│   │   ├── issue-1259-ci-fix-bash-spaces.bats
│   │   ├── issue-1260-daemon-set-e-corruption.bats
│   │   ├── issue-1261-validate-bash-timeout.bats
│   │   ├── issue-1262-bash-source-guard.bats
│   │   ├── issue-1270-node-grep-pattern.bats
│   │   ├── issue-1280-echo-dash-flags.bats
│   │   ├── multiline-json-grep.bats
│   │   ├── pr-merge-timeout.bats
│   │   ├── shfmt-hardcoded-indent.bats
│   │   ├── workflow-name-template.bats
│   │   └── yaml-bulk-multiline.bats
│   ├── fixtures/      # テスト用フィクスチャ
│   │   └── sample-config.yaml
│   └── test_helper.bash  # Bats共通ヘルパー
└── .worktrees/        # 実行時に作成されるworktreeディレクトリ
```

## 開発コマンド

```bash
# スクリプト実行
./scripts/run.sh 42

# 名前付きワークフローを指定
./scripts/run.sh 42 -w quick
./scripts/run.sh 42 -w frontend

# AI が自動的にワークフローを選択
./scripts/run.sh 42 -w auto

# 利用可能なワークフロー一覧
./scripts/run.sh --list-workflows

# テスト実行（推奨）
./scripts/test.sh              # 全テスト実行
./scripts/test.sh -v           # 詳細ログ付き
./scripts/test.sh -f           # fail-fast モード
./scripts/test.sh lib          # test/lib/*.bats のみ
./scripts/test.sh scripts      # test/scripts/*.bats のみ
./scripts/test.sh regression   # test/regression/*.bats のみ

# Batsテスト直接実行（--jobs で並列化推奨）
bats --jobs 4 test/**/*.bats

# 特定のテストファイル実行
bats test/lib/config.bats

# ShellCheck（静的解析）
./scripts/test.sh --shellcheck    # ShellCheckのみ実行
./scripts/test.sh --all           # Bats + ShellCheck
shellcheck -x scripts/*.sh lib/*.sh  # 直接実行

# 手動テスト
./scripts/list.sh -v
./scripts/status.sh 42

# 全セッションのマーカーチェック
./scripts/sweep.sh --dry-run
./scripts/sweep.sh --force

# 継続的改善
./scripts/improve.sh --max-iterations 1

# 複数セッション待機
./scripts/wait-for-sessions.sh 42 43
```

## コーディング規約

### シェルスクリプト

1. **shebang**: `#!/usr/bin/env bash`
2. **strict mode**: `set -euo pipefail`
   - **全てのファイル**（`scripts/` と `lib/` の両方）で使用する
   - `lib/` ファイルでも設定し、source先の環境に適用することで一貫性を保証する
   - これによりエラーの早期検出とデバッグの容易化を実現する
3. **関数定義**: 小文字のスネークケース
4. **変数**: ローカル変数は `local` を使用
5. **引数チェック**: 必須引数は明示的にチェック

### ファイル構成

- `scripts/` - ユーザーが直接実行するスクリプト
- `lib/` - 共通関数（sourceで読み込み）
- `docs/` - ドキュメント

## テスト

### Batsテストの書き方

> **Note**: 以下はサンプルコードです。`your-module.bats` は実際には存在しません。

```bash
#!/usr/bin/env bats
# test/lib/your-module.bats（架空の例）

load '../test_helper'

setup() {
    # テストごとのセットアップ
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
}

teardown() {
    # テストごとのクリーンアップ
    rm -rf "$BATS_TEST_TMPDIR"
}

@test "get_config returns default value" {
    source "$PROJECT_ROOT/lib/config.sh"
    load_config "$TEST_CONFIG_FILE"
    result="$(get_config worktree_base_dir)"
    [ "$result" = ".worktrees" ]
}

@test "run.sh shows help with --help" {
    run "$PROJECT_ROOT/scripts/run.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
```

### テスト実行

```bash
# 全テスト実行
./scripts/test.sh

# 特定のディレクトリを実行
./scripts/test.sh lib
./scripts/test.sh scripts

# 詳細出力
./scripts/test.sh -v
```

### モックの使用

```bash
# test_helper.bash のモック関数を使用
@test "example with mocks" {
    mock_gh      # ghコマンドをモック
    mock_tmux    # tmuxコマンドをモック
    enable_mocks # モックをPATHに追加
    
    # テストコード
}
```

### 手動テスト

```bash
# モック環境でテスト
export PI_COMMAND="echo pi"  # 実際のpiを起動しない
./scripts/run.sh 999 --no-attach
```

## デバッグ

```bash
# Bashデバッグモード
bash -x ./scripts/run.sh 42

# 詳細ログ
DEBUG=1 ./scripts/run.sh 42
```

## ワークフローカスタマイズ

### 新しいワークフローの追加

#### 方法1: `.pi-runner.yaml` の `workflows` セクション（推奨）

複数のワークフローを一箇所で管理できます：

```yaml
# .pi-runner.yaml
workflows:
  quick:
    description: 小規模修正（typo、設定変更、1ファイル程度の変更）
    steps:
      - implement
      - merge
  
  thorough:
    description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
    steps:
      - plan
      - implement
      - test
      - review
      - merge
  
  frontend:
    description: フロントエンド実装（React/Next.js、UIコンポーネント、スタイリング、画面レイアウト）
    steps:
      - plan
      - implement
      - review
      - merge
    context: |
      ## 技術スタック
      - React / Next.js / TypeScript
      - TailwindCSS
      
      ## 重視すべき点
      - レスポンシブデザイン
      - アクセシビリティ
      - コンポーネントの再利用性
```

**使用例**:
```bash
./scripts/run.sh 42 -w quick
./scripts/run.sh 42 -w frontend
./scripts/run.sh 42 -w auto  # AI が自動選択
```

#### 方法2: `workflows/` ディレクトリ（ファイル分散管理）

従来の方法も引き続きサポートされます：

```yaml
# workflows/thorough.yaml
name: thorough
description: 徹底ワークフロー（計画・実装・テスト・レビュー・マージ）
steps:
  - plan
  - implement
  - test
  - review
  - merge
```

> **Note**: `-w NAME` 指定時、`.pi-runner.yaml` の `workflows.{NAME}` が `workflows/{NAME}.yaml` より優先されます。

#### エージェントテンプレートの追加

必要に応じて `agents/` ディレクトリにエージェントテンプレートを追加します

### エージェントテンプレートの作成

```markdown
# agents/test.md
# Test Agent

GitHub Issue #{{issue_number}} のテストを実行します。

## コンテキスト
- **Issue番号**: #{{issue_number}}
- **ブランチ**: {{branch_name}}

## タスク
1. 単体テストを実行
2. 結合テストを実行
3. カバレッジレポートを確認
```

### テンプレート変数

| 変数 | 説明 | ビルトイン使用 |
|------|------|----------------|
| `{{issue_number}}` | GitHub Issue番号 | ✅ |
| `{{pr_number}}` | PR番号 | ✅（ci-fix） |
| `{{issue_title}}` | Issueタイトル | ✅ |
| `{{branch_name}}` | ブランチ名 | ✅ |
| `{{worktree_path}}` | worktreeのパス | ✅ |
| `{{plans_dir}}` | 計画書ディレクトリパス | ✅ |
| `{{signal_dir}}` | シグナルファイルディレクトリパス | ✅ |
| `{{step_name}}` | 現在のステップ名 | *カスタム用 |
| `{{workflow_name}}` | ワークフロー名 | *カスタム用 |

> **Note**: 「カスタム用」の変数は `lib/workflow.sh` でサポートされていますが、ビルトインのエージェントテンプレート（`agents/*.md`）では使用していません。カスタムワークフローでロギングやデバッグ用途に活用できます。

### ワークフロー検索順序

#### `-w` オプション未指定時（デフォルトワークフロー）

1. `.pi-runner.yaml` の `workflow` セクション
2. `.pi/workflow.yaml`
3. `workflows/default.yaml`
4. ビルトイン `default`

#### `-w NAME` 指定時（名前付きワークフロー）

1. **`.pi-runner.yaml` の `workflows.{NAME}`**（最優先）
2. `.pi/workflow.yaml`
3. `workflows/{NAME}.yaml`
4. ビルトイン `{NAME}`

#### `-w auto` 指定時（AI 自動選択）

`.pi-runner.yaml` の `workflows` セクション全体を読み取り、AI が Issue 内容に基づいて最適なワークフローを選択します。

> **推奨**: 複数のワークフローを使用する場合、`.pi-runner.yaml` の `workflows` セクションで一箇所管理するのが推奨されます。

## ShellCheck

### インストール

```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
sudo apt-get install shellcheck

# その他
# https://github.com/koalaman/shellcheck#installing
```

### 実行方法

```bash
# test.shから実行（推奨）
./scripts/test.sh --shellcheck    # ShellCheckのみ
./scripts/test.sh --all           # Bats + ShellCheck

# 直接実行
shellcheck -x scripts/*.sh lib/*.sh
```

### 設定ファイル

プロジェクトルートの `.shellcheckrc` で設定を管理しています：

```bash
# ソースファイルを追跡
external-sources=true

# 無効化している警告
# SC1091: ソースファイルが見つからない（-x オプションで対応）
# SC2016: シングルクォート内で変数展開されない（正規表現で意図的に使用）
```

### CI統合

GitHub Actions で自動的にShellCheckが実行されます。
PRをマージする前に警告が解消されている必要があります。

## 既知の制約

<!-- エージェントが重要な知見を発見した際、ここに1行サマリーとリンクを追加する -->
<!-- 例: - playwright-cli 0.0.63+: デフォルトセッション使用必須 → [詳細](docs/decisions/001-playwright-session.md) -->
- Bats並列テスト: 16ジョブでハング、デフォルト2ジョブ推奨 → [詳細](docs/decisions/001-test-parallel-jobs-limit.md)
- マーカー検出: pipe-pane+grepで全出力を記録・検索、代替パターンも検出 → [詳細](docs/decisions/002-marker-detection-reliability.md)
- 完了検出: シグナルファイル最優先、テキストマーカーはフォールバック → [詳細](docs/decisions/003-signal-file-completion.md)
- 004: AIエージェントによるファイル誤上書き事故 (2026-02-10) -> [詳細](docs/decisions/004-accidental-file-overwrite.md)
- 003: シグナルファイルによる完了検出 (2026-02-10) -> [詳細](docs/decisions/003-signal-file-completion.md)
- 002: マーカー検出の信頼性とパフォーマンス改善 (2026-02-08) -> [詳細](docs/decisions/002-marker-detection-reliability.md)
- ファイル誤上書き防止: コミット前に `git diff --stat` で無関係な変更がないか必ず確認 → [詳細](docs/decisions/004-accidental-file-overwrite.md)
## 注意事項

- すべてのスクリプトは `set -euo pipefail` で始める
- 外部コマンドの存在確認を行う
- エラーメッセージは stderr に出力
- 終了コードを適切に設定する
- ShellCheck警告は意図的な場合を除き修正する
